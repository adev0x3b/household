# frozen_string_literal: true

require "test_helper"

# What a reminder mail says: what each kind lets a mail say of its thing,
# when it is due on the person's clock, and a subject that says only that
# it is a reminder.
class Emails::RemindersWordingTest < ActiveSupport::TestCase
  # The kinds a reminder mail may name. A kind is listed here only when its
  # name can't tell of anyone's health.
  NAMED = %w[Task Meal Transaction].freeze
  SATURDAY = Date.new(2026, 10, 31)

  setup do
    @alice = profiles(:alice)
    @rome = ActiveSupport::TimeZone["Europe/Rome"]
  end

  test "every kind says what a reminder mail calls one of its days, in every language; a kind that could tell of someone's health never names it" do
    Event.types.each do |kind|
      assert_equal NAMED.include?(kind.name), kind.named_in_mail?, kind.name
      event = series!(kind.name, profile: @alice, starts_on: SATURDAY, title: "Kept to the app")
      day = event.occurrence_on(SATURDAY, time: nil)

      I18n.available_locales.each do |locale|
        assert I18n.exists?("#{kind.model_name.route_key}.reminder_mail.thing", locale), "#{kind.name} (#{locale})"
        thing = I18n.with_locale(locale) { event.reminder_mail_thing(day) }
        assert_equal NAMED.include?(kind.name), thing.include?("Kept to the app"), "#{kind.name} (#{locale}): #{thing}"
      end
    end
  end

  test "a payment for something a mail doesn't name, or for a supply bought, is only “your payment”: the app titles it after what it pays for" do
    unnamed = [ series!("Appointment", profile: @alice, starts_on: SATURDAY, title: "Dr. Rossi, psychiatry").occurrence_on(SATURDAY, time: nil),
                medication.occurrence_on(SATURDAY, time: "14:30"),
                series!("LabTestResult", profile: @alice, starts_on: SATURDAY, title: "Thyroid panel").occurrence_on(SATURDAY, time: nil),
                supply_purchase!(profile: @alice, name: "Levothyroxine 75 mcg") ]
    named = [ task("Fix the sink").occurrence_on(SATURDAY, time: nil), ingredient_purchase!(profile: @alice) ]

    unnamed.each do |about|
      thing, title = payment_for(about)
      assert_equal "your payment", thing, title
    end
    named.each do |about|
      thing, title = payment_for(about)
      assert_equal "your payment “#{title}”", thing
    end
  end

  test "a payment saved with no mark, as by the version before, is only “your payment” while what it pays for is there" do
    visit = series!("Appointment", profile: @alice, starts_on: SATURDAY, title: "Dr. Rossi, psychiatry").occurrence_on(SATURDAY, time: nil)
    [ visit, supply_purchase!(profile: @alice, name: "Levothyroxine 75 mcg") ].each do |about|
      cost = cost_for(about)
      Transaction::Details.where(event_id: cost.event_id).update_all(named_in_mail: true)

      cost = Occurrence.find(cost.id)
      assert_equal "your payment", cost.event.reminder_mail_thing(cost), cost.event.title
    end
  end

  test "a payment kept once what it paid for is deleted is still only “your payment”: its title is still the one made after it" do
    visit = series!("Appointment", profile: @alice, starts_on: SATURDAY, title: "Dr. Rossi, psychiatry")
    pills = medication
    levothyroxine = supply_purchase!(profile: @alice, name: "Levothyroxine 75 mcg")
    costs = [ visit.occurrence_on(SATURDAY, time: nil), pills.occurrence_on(SATURDAY, time: "14:30"), levothyroxine ].map { cost_for(_1) }

    Occurrences::Destroy.call(visit.occurrences.to_a, by: @alice, scope: :series)
    Occurrences::Destroy.call(pills.occurrences.to_a, by: @alice, scope: :series)
    levothyroxine.destroy!

    costs.map { Occurrence.find(_1.id) }.each do |cost|
      assert_nil cost.event.about_for(cost), cost.event.title
      assert_equal "your payment", cost.event.reminder_mail_thing(cost), cost.event.title
    end
  end

  test "one reminder is a sentence saying when it is due, at its hour when it has one; the subject says only that it is a reminder" do
    pill = wording(due(medication, at: [ 14, 30 ], timed: true))
    rent = wording(due(task("Pay the rent"), at: [ 9, 0 ], timed: false))

    assert_equal "A reminder from Household", pill.subject
    assert_equal [ "This is your reminder for your medication at 14:30 on Saturday 31 October." ], pill.paragraphs
    assert_equal [ "This is your reminder for your task “Pay the rent” on Saturday 31 October." ], rent.paragraphs
    assert_empty pill.items
    assert_equal [ "Open it in Household", "http://example.com/calendar" ], pill.action.to_h.values
    assert_equal [ "Stop every reminder by email", "http://example.com/stop" ], pill.unsubscribe.to_h.values
  end

  test "several are a list in the order given, in the person's language" do
    wording = I18n.with_locale(:it) do
      wording(due(task("Pagare l'affitto"), at: [ 9, 0 ], timed: false), due(medication, at: [ 14, 30 ], timed: true))
    end

    I18n.with_locale(:it) do
      assert_equal "2 promemoria da Household", wording.subject
      assert_equal [ "Questi sono i tuoi promemoria:" ], wording.paragraphs
      assert_equal [ "La tua attività “Pagare l'affitto”, sabato 31 ottobre", "Il tuo farmaco, sabato 31 ottobre alle 14:30" ], wording.items
      assert_equal "Apri il tuo calendario", wording.action.label
    end
  end

  test "the plain text holds every part, each link written out under its label" do
    text = wording(due(medication, at: [ 14, 30 ], timed: true)).text

    assert_equal <<~TEXT.chomp, text
      Hello Alice,

      This is your reminder for your medication at 14:30 on Saturday 31 October.

      Open it in Household:
      http://example.com/calendar

      You asked for this reminder by email. To stop it, untick “Also by email” in its form.

      Stop every reminder by email:
      http://example.com/stop
    TEXT
  end

  private

  def task(title) = series!("Task", profile: @alice, starts_on: SATURDAY, title: title)
  def medication = series!("Medication", profile: @alice, starts_on: SATURDAY, title: "Methotrexate", slots: %w[14:30])

  # A payment for `about`, titled as its form titles it.
  def cost_for(about)
    title = about.is_a?(Occurrence) ? about.event.cost_title(about) : about.cost_title
    Transactions::SetCost.call(about, date: SATURDAY, title: title, amount: "30", payment_method: "card").cost
  end

  # What a reminder mail calls the day of a payment for `about`, and its title.
  def payment_for(about)
    cost = cost_for(about)
    [ cost.event.reminder_mail_thing(cost), cost.event.title ]
  end

  def due(event, at:, timed:)
    day = event.occurrence_on(SATURDAY, time: (format("%02d:%02d", *at) if event.slots.any?))
    Reminders::StillDue::Reminder.new(row: nil, occurrence: day, due_at: @rome.local(2026, 10, 31, *at), timed: timed)
  end

  def wording(*reminders)
    Emails::RemindersWording.new(@alice, reminders: reminders, calendar_url: "http://example.com/calendar", unsubscribe_url: "http://example.com/stop")
  end
end
