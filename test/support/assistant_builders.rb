# frozen_string_literal: true

# Helpers for assistant tests. Tools are called directly (as RubyLLM would,
# with the model's arguments), so no test ever talks to a model.
module AssistantBuilders
  def assistant_chat(profile, locale: :en)
    Assistant::Chat.start!(profile: profile, locale: locale, time_zone: "Europe/Rome")
  end

  # Hands operations to the change-set backend the way every write tool does
  # (Assistant::ChangeSets::Submit), in the tools' { ok:, data: } shape.
  def submit_changes(chat, operations, confirm: false)
    { ok: true, data: Assistant::ChangeSets::Submit.call(chat: chat, operations: operations, confirm: confirm) }
  rescue Assistant::ChangeSets::Submit::Mistake => e
    { ok: false, error: e.message }
  end

  # Calls a tool the way the model would and returns its { ok:, data: } hash.
  def run_tool(tool, chat, **arguments)
    "Assistant::#{tool.to_s.camelize}Tool".constantize.new(chat: chat).call(**arguments)
  end

  # The saved days of a kind's series (the profile's, when given), in order.
  def days_of(kind, profile = nil)
    scope = Occurrence.of_type(kind)
    scope = scope.where(events: { profile_id: profile.id }) if profile
    scope.order(:date, :time, :id)
  end

  # The saved appointment days with this counterpart (as each day reads it).
  def appointments_with(counterpart)
    days_of(Appointment).with_series(Appointment)
      .where("#{Occurrence.resolved_sql(:counterpart, type: Appointment)} = ?", counterpart)
  end

  # A lab result saved on `date` with its values ({ "Calcium" => "300" }); returns its day.
  def lab_result!(profile:, date:, values: {}, title: "Panel", status: :pending)
    event = LabTestResult.create!(profile: profile, starts_on: date, title: title)
    day = event.occurrence_on(date)
    day.status = status
    day.completed_at = date.in_time_zone.change(hour: 12) if day.completed?
    values.each { |name, value| day.lab_test_result_entries.build(analyte: Analyte.find_or_create_by_name(name, profile_id: profile.id), value: value) }
    day.save!
    day
  end

  # A cost's amount and how it was paid (a Transaction's day).
  def amount_of(cost) = cost&.details&.amount
  def paid_with(cost) = cost&.details&.payment_method
end
