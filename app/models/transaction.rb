# frozen_string_literal: true

# Money moving on a day: an expense or an income, once or every month,
# possibly about something (a visit's fee, a purchase — Costable) and
# possibly between two housemates. A payment between housemates is one
# fact with two readers: the counterparty sees the same series
# (Event.accessible_by), read-only, with the kind flipped for them
# (kind_for). An amount is stored without a sign: the kind says which way
# the money went, and whoever shows or sums it signs it from the viewer's
# side (signed_cents_for, viewer_amount_sql). Finance.
class Transaction < Event
  CURRENCY_SCALE = 100

  has_details "Transaction::Details"

  validates :title, presence: true

  def self.section = :finance
  def self.policy_class = TransactionOccurrencePolicy
  def self.costable? = false

  # A card nests a payment inside what it pays for: what its day's details
  # or its series' are about (#about_for).
  def self.preload_for_cards(days)
    rows = days.flat_map { |day| [ day.own_details, day.event.details ] }.compact.uniq
    ActiveRecord::Associations::Preloader.new(records: rows, associations: :about).call
  end

  def self.amount_to_cents(value)
    return if value.blank?

    decimal = BigDecimal(value.to_s)
    (decimal * CURRENCY_SCALE).round(0, BigDecimal::ROUND_HALF_UP).to_i
  rescue ArgumentError
    nil
  end

  # The amount of a day as its owner reads it, in cents with its sign
  # (negative for an expense), over Occurrence.with_series(Transaction).
  def self.owner_amount_sql
    cents = Occurrence.resolved_sql(:amount_cents, type: self)
    kind = Occurrence.resolved_sql(:kind, type: self)
    "CASE #{kind} WHEN #{Details.kinds.fetch("expense")} THEN -(#{cents}) ELSE #{cents} END"
  end

  # The amount of a day as `viewer` reads it, in cents with its sign, over
  # Occurrence.with_series(Transaction): negated for the counterparty.
  def self.viewer_amount_sql(viewer)
    owner = owner_amount_sql
    "CASE WHEN transaction_details_series.counterparty_profile_id = #{viewer.id.to_i} THEN -(#{owner}) ELSE #{owner} END"
  end

  # The kind of a day as `viewer` reads it (expense ↔ income for the
  # counterparty), over Occurrence.with_series(Transaction).
  def self.viewer_kind_sql(viewer)
    kind = Occurrence.resolved_sql(:kind, type: self)
    income, expense = Details.kinds.values_at("income", "expense")
    flipped = "CASE #{kind} WHEN #{income} THEN #{expense} ELSE #{income} END"
    "CASE WHEN transaction_details_series.counterparty_profile_id = #{viewer.id.to_i} THEN #{flipped} ELSE #{kind} END"
  end

  def counterparty?(viewer) = viewer.present? && details.counterparty_profile_id == viewer.id

  # The kind as `viewer` reads it: the series', or a day's when given its
  # details (a day may have its own).
  def kind_for(viewer, details = self.details)
    counterparty?(viewer) ? Details.opposite_kind(details.kind) : details.kind
  end

  # Whether `viewer` reads the money as coming in, so its done word is
  # "received" rather than "paid".
  def received_by?(viewer, details = self.details) = kind_for(viewer, details) == "income"

  def completion_notice_key(completed, occurrence, viewer)
    return super unless received_by?(viewer, occurrence.details)

    "transactions.notices.#{completed ? "received" : "unreceived"}"
  end

  # The amount in cents as `viewer` reads it, negative when the money went
  # out: the series', or a day's when given its details.
  def signed_cents_for(viewer, details = self.details)
    cents = details.amount_cents
    kind_for(viewer, details) == "expense" ? -cents : cents
  end

  # The counterparty sees it on their calendar.
  def extra_readers = [ details.counterparty_profile ].compact

  def self.preload_audience(events)
    preload_series(events)
    ActiveRecord::Associations::Preloader.new(records: events.map(&:details), associations: :counterparty_profile).call
  end

  # What a day of it pays for: its own row's thing, else the series' thing
  # (a series it's about → that series' same day; a purchase as is).
  def about_for(occurrence)
    own = occurrence.own_details&.about
    return own if own

    about = details.about
    about.is_a?(Event) ? about.occurrence_on(occurrence.date) : about
  end

  def about_day(occurrence)
    about = about_for(occurrence)
    about if about.is_a?(Occurrence)
  end

  def about_label
    about = details.about
    return if about.nil?

    about.respond_to?(:event_label) ? about.event_label : about.class.model_name.human
  end
end
