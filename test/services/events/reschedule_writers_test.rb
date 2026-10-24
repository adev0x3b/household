# frozen_string_literal: true

require "test_helper"

# A series with a past keeps it whoever edits its repeat: the form, the
# assistant, or a linked housemate whose change the owner approves. Each
# writer says the same edit in its own words, and each is held to one
# table of outcomes, so a new writer joins the table rather than bringing
# tests of its own.
class Events::RescheduleWritersTest < ActiveSupport::TestCase
  EDITS = {
    "another weekday" => { form: { event: { frequency: "weekly", week_days: %w[wednesday] } },
                           assistant: { recurrence: { frequency: "weekly", week_days: %w[wednesday] } },
                           continued: { rrule: "FREQ=WEEKLY;BYDAY=WE", slots: [ [ "08:00", nil ] ] } },
    "another time" => { form: { event: { frequency: "daily", slots: [ "09:00" ], slots_submitted: "1" } },
                        assistant: { recurrence: { times_of_day: %w[09:00] } },
                        continued: { rrule: "FREQ=DAILY", slots: [ [ "09:00", nil ] ] } },
    "an end" => { form: { event: { frequency: "daily", ends: "2026-10-31" } },
                  assistant: { recurrence: { ends: "2026-10-31" } },
                  in_place: { ends: Date.new(2026, 10, 31) } },
    "the same repeat again" => { form: { event: { frequency: "daily", slots: [ "08:00" ], slots_submitted: "1" } },
                                 assistant: { recurrence: { frequency: "daily", times_of_day: %w[08:00] } },
                                 in_place: { ends: nil } }
  }.freeze

  setup do
    travel_to Time.zone.local(2026, 10, 7, 12)
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @today = Date.current
    @event = series!("Medication", profile: @alice, starts_on: @today - 14, title: "Glipizide", slots: %w[08:00], rrule: "FREQ=DAILY")
    @event.occurrences_between(@event.starts_on, @today - 1).each(&:complete!)
    @dose = day!(@event, date: @today, time: "08:00")
    link!(@bob, @alice)
    grant(@alice, @bob, "Medication", write: :ask)
  end

  def unfinished
    Reports::Unfinished.new(Reports::Audience.new(viewer: @alice), today: @today).entries(of: Medication) { _1.id == @event.id }
  end

  def form_params(edit) = { medication: { apply_to: "series" }, **edit[:form] }

  def through_the_form(edit)
    form = Occurrences::FormSave.for("Medication").new(actor: @alice, params: form_params(edit), record: @dose)
    assert form.save, form.record.errors.full_messages.to_sentence
  end

  def through_the_assistant(edit)
    data = Assistant::ChangeSets::Submit.call(chat: assistant_chat(@alice), confirm: true,
                                              operations: [ { op: "update", type: "medication", ref: @dose.id, fields: edit[:assistant] } ])
    assert_equal "waiting_for_user", data[:status].to_s, "Bob reads Alice's medications through the link: #{data.inspect}"
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(data[:change_set_id]), confirmed: true)
  end

  def through_an_approval(edit)
    form = Occurrences::FormSave.for("Medication").new(actor: @bob, params: form_params(edit), record: @dose)
    assert_predicate form, :valid_for_hold?
    approval = Links::Approvals::Hold.call(requester: @bob, record: @dose, kind: :update, payload: form.payload, preview: form.preview)
    Links::Approvals::Decide.call(approval, approve: true)
    assert_predicate approval.reload, :approved?, approval.failure.to_s
  end

  WRITERS = %i[through_the_form through_the_assistant through_an_approval].freeze

  EDITS.each do |name, edit|
    WRITERS.each do |writer|
      test "#{name} #{writer.to_s.tr("_", " ")} keeps the series' past" do
        assert_empty unfinished

        public_send(writer, edit)

        assert_empty unfinished, "the mornings taken at 08:00 are owed nothing"
        assert_equal 14, @event.occurrences.completed.count
        if edit[:continued]
          continued = Medication.where(profile: @alice, title: "Glipizide").where.not(id: @event.id).sole
          assert_equal [ @today, edit[:continued][:rrule], edit[:continued][:slots] ], [ continued.starts_on, continued.rrule, continued.slots ]
          assert_equal @today - 1, Events::RecurrenceRule.describe(@event.reload.rrule)[:ends], "the series ended yesterday"
        else
          assert_equal [ 1, edit[:in_place][:ends] ],
                       [ Medication.where(profile: @alice, title: "Glipizide").count, Events::RecurrenceRule.describe(@event.reload.rrule)[:ends] ]
        end
      end
    end
  end
end
