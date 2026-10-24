# frozen_string_literal: true

module Reports
  # Something a dashboard says needs attention — a dose missed, a payment
  # overdue, a supply running out — the same shape from every section, so
  # one list renders them all (Views::Home::AttentionList).
  #
  # `kind` names the sentence the page words it with, and `words` holds what
  # that sentence fills in (a lab value, the ingredients short) beside the
  # date, which every sentence may use. `occurrence` is the day it is about,
  # saved or projected; an item about a supply has none. `opens` is what the
  # page opens in place for it: that day, unless the item says otherwise (a
  # supply to buy more of, the purchase a batch came from). `count` is how
  # many days of the series are in the same state, this one the newest.
  # `resolvable` says the list may settle it on the spot, marking the
  # series' days still to do as skipped (Attention::Resolve): true of a day
  # that has passed and was never recorded, never of what is still to come,
  # was already skipped, or is about a supply or a value.
  class AttentionItem < Data.define(:kind, :severity, :subject, :date, :occurrence, :opens, :count, :words, :resolvable)
    SEVERITY_ORDER = { critical: 0, warning: 1 }.freeze

    def initialize(kind:, severity:, subject:, date:, occurrence: nil, opens: occurrence, count: 1, words: {}, resolvable: false) = super

    # Most urgent first, then the nearest to today: yesterday's missed dose
    # before last spring's, a batch expiring this week before next month's
    # (an undated item counts as today).
    def self.sorted(items, today:) = items.sort_by { |item| [ SEVERITY_ORDER.fetch(item.severity), ((item.date || today) - today).abs ] }
  end
end
