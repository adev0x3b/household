# frozen_string_literal: true

# Something money can be about: a day of a series (a visit's fee, a meal
# out, a task's expense), a supply purchase, a grocery purchase. The cost is
# a Transaction: its series' details row says what series or purchase it is
# about, a day's override row says which day (Transaction::Details#about).
#
#   appointment_day.costs       # => the Transaction days paying for it
#   purchase.costs.first
#
# A Transaction's own days take no costs (Transaction.costable? is false).
module Costable
  extend ActiveSupport::Concern

  included do
    has_many :cost_details, as: :about, class_name: "Transaction::Details", dependent: :nullify
  end

  # Whether money can be about it. A purchase always takes costs; a day
  # answers for its kind.
  def costable? = true

  # Whether a reminder mail may name a payment for it, which the app titles
  # after it (Transaction#reminder_mail_thing): only what says so, since a
  # supply bought may be a medication.
  def named_in_mail? = false

  # The Transaction days paying for this thing, earliest first: the days
  # whose own row names it, and — for a day of a series — the same-day
  # days of the Transaction series whose series' row names its series.
  def costs
    return @costs if defined?(@costs)
    return Occurrence.none unless costable?

    rows = Transaction::Details.where(about: self)
    scope = Occurrence.where(id: rows.overrides.select(:occurrence_id))
    scope = if is_a?(Occurrence)
      series_rows = Transaction::Details.series.where(about: event)
      scope.or(Occurrence.where(event_id: series_rows.select(:event_id), date: date))
    else
      scope.or(Occurrence.where(event_id: rows.series.select(:event_id)))
    end
    scope.in_order
  end

  # The one cost most forms show (a visit has one fee): read for many
  # records at once by Costable.preload_cost, else asked here.
  def cost
    return @cost if defined?(@cost)

    @cost = costs.first
  end

  attr_writer :cost, :costs

  def reload(...)
    remove_instance_variable(:@cost) if defined?(@cost)
    remove_instance_variable(:@costs) if defined?(@costs)
    super
  end

  # Every cost of each of many records, in a few queries, for a change that
  # walks many days at once (Attention::Resolve): each day's own status
  # change then settles its costs from what was loaded. A day not saved yet
  # can still have costs, through its series' row.
  def self.preload_costs(records)
    records = records.select(&:costable?)
    return if records.empty?

    costs = Costs.new(records)
    records.each { |record| record.costs = costs.all_for(record) }
  end

  # The first cost of each of many records of one class (a page of the
  # assistant's summaries), in a few queries — the same days #costs finds,
  # earliest first, with what reading them needs.
  def self.preload_cost(records)
    records = records.select(&:persisted?)
    records = records.select(&:costable?)
    return if records.empty?

    costs = Costs.new(records)
    records.each { |record| record.cost = costs.first_for(record) }
  end

  # The costs of many records, found as #costs finds one's.
  class Costs
    def initialize(records)
      @records = records
      @days = records.first.is_a?(Occurrence)
      type = @days ? "Occurrence" : records.first.class.base_class.name
      rows = Transaction::Details.where(about_type: type, about_id: records.map(&:id)).pluck(:about_id, :occurrence_id, :event_id)
      # A day's own row names that day; a series' row names a purchase, or —
      # for a day — the day's series (its same-date days pay for it).
      own, series = rows.partition { |_, occurrence_id, _| occurrence_id }
      @own = own.group_by(&:first).transform_values { |found| found.map { |_, occurrence_id, _| occurrence_id } }
      @series = @days ? series_about_events : series.group_by(&:first).transform_values { |found| found.map(&:last) }
    end

    def first_for(record) = all_for(record).first

    def all_for(record)
      own = @own.fetch(record.id, [])
      series = @series.fetch(@days ? record.event_id : record.id, [])
      candidates.select { |day| own.include?(day.id) || (series.include?(day.event_id) && (!@days || day.date == record.date)) }
    end

    private

    def series_about_events
      Transaction::Details.series.where(about_type: "Event", about_id: @records.map(&:event_id).uniq).pluck(:about_id, :event_id)
        .group_by(&:first).transform_values { |found| found.map(&:last) }
    end

    def candidates
      @candidates ||= begin
        scope = Occurrence.where(id: @own.values.flatten)
        events = @series.values.flatten.uniq
        scope = scope.or(@days ? Occurrence.where(event_id: events, date: @records.map(&:date).uniq) : Occurrence.where(event_id: events)) if events.any?
        days = scope.includes(:event).in_order.to_a
        Event.preload_series(days.map(&:event).uniq)
        Occurrence.preload_details(days)
      end
    end
  end
end
