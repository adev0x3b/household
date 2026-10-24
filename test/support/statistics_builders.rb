# frozen_string_literal: true

# Builders for tests. They create the minimum valid rows so each test states
# only what matters: a series of a kind (an Event subclass with its series
# details) and, for the day builders, its stored day — the Occurrence they
# return. The series is `occurrence.event`.
module StatisticsBuilders
  # What a kind's series details need when a test doesn't say.
  DEFAULT_DETAILS = {
    "Medication" => { kind: :pill },
    "Transaction" => { kind: :expense, category: :miscellaneous, amount: "10", currency: "EUR", payment_method: :card }
  }.freeze

  def audience_for(profile, member: nil)
    Reports::Audience.new(viewer: profile, member_id: member&.id)
  end

  def period(start_date, end_date)
    Reports::Period.new(start_date: start_date, end_date: end_date)
  end

  # A series of `type`, one-off unless `rrule:` is given.
  def series!(type, profile:, starts_on:, title: "Series", rrule: nil, collection: nil, slots: [], **details)
    klass = type.to_s.constantize
    klass.create!(
      profile: profile, starts_on: starts_on, title: title, rrule: rrule, collection: collection,
      event_slots: EventSlot.rows_for(slots),
      details_attributes: DEFAULT_DETAILS.fetch(klass.name, {}).merge(details)
    )
  end

  def weekly_event(profile:, type:, starts_on:, title: "Weekly", **details)
    series!(type, profile: profile, starts_on: starts_on, title: title, rrule: "FREQ=WEEKLY", **details)
  end

  # A stored day of `event` (built unless given), with its status.
  def day!(event, date:, status: :pending, completed_on: nil, time: nil, anchor: nil)
    occurrence = event.occurrence_on(date, time: time, anchor: anchor)
    occurrence.status = status
    occurrence.completed_at = completed_on&.in_time_zone&.change(hour: 12) || (date.in_time_zone.change(hour: 12) if status.to_s == "completed")
    occurrence.save!
    occurrence
  end

  # A medication taken every day at set times ("08:00", or an anchor such
  # as "CV" — see Events::TimesOfDay), its first dose saved; returns it.
  def timed_medication!(profile:, starts_on:, times:, name: "Metformin", ends: nil)
    event = series!("Medication", profile: profile, starts_on: starts_on, title: name, slots: times,
                                  rrule: Events::RecurrenceRule.build(frequency: "daily", ends: ends))
    day!(event, date: starts_on, time: event.first_slot.first, anchor: event.first_slot.last)
  end

  def medication!(profile:, date:, status: :pending, completed_on: nil, event: nil, name: "Cobalamin", **details)
    event ||= series!("Medication", profile: profile, starts_on: date, title: name, **details)
    day!(event, date: date, status: status, completed_on: completed_on)
  end

  def task!(profile:, date:, status: :pending, priority: :medium, title: "Laundry", event: nil)
    event ||= series!("Task", profile: profile, starts_on: date, title: title, priority: priority)
    day!(event, date: date, status: status)
  end

  def appointment!(profile:, date:, status: :pending, collection: nil, counterpart: nil, kind: :medical, title: "Checkup", start_time: nil)
    event = series!("Appointment", profile: profile, starts_on: date, title: title, collection: collection, kind: kind, counterpart: counterpart)
    event.update!(start_time: start_time) if start_time
    day!(event, date: date, status: status)
  end

  # An expense (its day, completed unless said otherwise), possibly about
  # something: a day of another series, or a purchase.
  def expense!(profile:, date:, cents:, currency: "EUR", status: :completed, category: :healthcare, about: nil, event: nil, title: "Cost")
    event ||= series!("Transaction", profile: profile, starts_on: date, title: title, kind: :expense, category: category,
                                     amount_cents: cents, currency: currency, payment_method: :card,
                                     about: (about.is_a?(Occurrence) ? about.event : about))
    occurrence = day!(event, date: date, status: status)
    occurrence.write_details!(about: about) if about.is_a?(Occurrence)
    occurrence
  end

  def income!(profile:, date:, cents:, currency: "EUR", status: :completed, category: :salary, event: nil, title: "Payment")
    event ||= series!("Transaction", profile: profile, starts_on: date, title: title, kind: :income, category: category,
                                     amount_cents: cents, currency: currency, payment_method: :bank_transfer)
    day!(event, date: date, status: status)
  end

  # An expense the payer logs against a household member: one series, two
  # readers (the counterparty sees it as an income). Returns the payer's day.
  def transfer!(payer:, counterparty:, date:, cents:, currency: "EUR", category: :groceries, status: :completed)
    event = series!("Transaction", profile: payer, starts_on: date, title: "Shared cost", kind: :expense, category: category,
                                   amount_cents: cents, currency: currency, payment_method: :card, counterparty_profile: counterparty)
    day!(event, date: date, status: status)
  end

  def supply_purchase!(profile:, name:, quantity: 10, remaining: nil, collection: nil, expires_on: nil, threshold: nil, purchased_on: Date.new(2025, 1, 1))
    supply = Supply.create!(profile: profile, name: name, category: :medication, unit_label: "vial", low_stock_threshold: threshold)
    SupplyPurchase.create!(
      supply: supply, profile: profile, collection: collection, quantity_purchased: quantity,
      quantity_remaining: remaining || quantity, purchased_on: purchased_on, expires_on: expires_on,
    )
  end

  def ingredient_purchase!(profile:, name: "Flour", quantity: 1, unit: "kg", purchased_on: Date.new(2025, 1, 1))
    ingredient = Ingredient.find_or_create_by_name(name, profile_id: profile.id)
    ingredient.update!(unit_name: unit) if ingredient.unit.nil? && unit
    ingredient.ingredient_purchases.create!(profile: profile, quantity: quantity, purchased_on: purchased_on)
  end
end
