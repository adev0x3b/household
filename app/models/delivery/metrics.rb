# frozen_string_literal: true

module Delivery
  # DORA's four keys for production, read from the deployments kamal.yml
  # records. Each is a Reports::Metric, so the console draws them with the
  # dashboards' own tiles.
  class Metrics
    WINDOW = 13.weeks
    PERIOD = 30.days
    BUCKET = 1.week
    # A change rolled back within this long counts as failed, even though its
    # own run succeeded.
    RELAPSE = 1.day
    # A rehearsal or a restart leaves production running what it ran, so
    # neither is a deployment.
    DEPLOYMENTS = %w[deploy release rollback].freeze
    # A rollback undoes a change rather than making one.
    CHANGES = %w[deploy release].freeze
    LOOKBACK = 100

    Lead = Data.define(:at, :days)
    Recovery = Data.define(:at, :hours)

    # records: production's, any order; commits_between(from, to) → [Commit].
    def initialize(records:, now: Time.current, &commits_between)
      @records = records.select { _1.environment == "production" && !_1.live? && _1.finished_at }.sort_by(&:finished_at)
      @now = now
      @commits_between = commits_between
    end

    def self.for_production(now: Time.current)
      new(records: Github.records(environment: "production", limit: LOOKBACK), now: now) { |from, to| Github.compare(from, to).commits }
    end

    def all = { frequency: frequency, lead_time: lead_time, failure_rate: failure_rate, recovery_time: recovery_time }

    def frequency
      metric(deployments.map(&:finished_at), format: :count, polarity: :higher_is_better) { |times| times.size }
    end

    def lead_time
      metric(leads, format: :days, polarity: :lower_is_better, at: :at) { |found| median(found.map(&:days)) }
    end

    def failure_rate
      metric(changes, format: :percent, polarity: :lower_is_better, at: :finished_at) do |found|
        (found.count { failed?(_1) } * 100.0 / found.size).round if found.any?
      end
    end

    def recovery_time
      metric(recoveries, format: :hours, polarity: :lower_is_better, at: :at) { |found| median(found.map(&:hours)) }
    end

    def deployments = @records.select { DEPLOYMENTS.include?(_1.task) && _1.succeeded? }
    def changes = @records.select { CHANGES.include?(_1.task) }

    # Failed outright, or a rollback followed it within a day.
    def failed?(record)
      return true if record.failed?

      record.succeeded? && @records.any? { _1.task == "rollback" && _1.succeeded? && _1.finished_at > record.finished_at && _1.finished_at <= record.finished_at + RELAPSE }
    end

    # Each commit a successful change shipped, with how long it waited.
    def leads
      @leads ||= deployments.select { CHANGES.include?(_1.task) }.flat_map do |record|
        previous = deployments.select { _1.finished_at < record.finished_at }.last
        next [] if previous.nil?

        @commits_between.call(previous.sha, record.sha).filter_map do |commit|
          next unless commit.committed_at && commit.committed_at <= record.finished_at

          Lead.new(at: record.finished_at, days: (record.finished_at - commit.committed_at) / 1.day)
        end
      end
    end

    # Each failed change, with how long until production succeeded again.
    def recoveries
      @recoveries ||= changes.select { failed?(_1) }.filter_map do |failure|
        repaired = deployments.find { _1.finished_at > failure.finished_at }
        next if repaired.nil?

        Recovery.new(at: repaired.finished_at, hours: (repaired.finished_at - failure.finished_at) / 1.hour)
      end
    end

    private

    # A metric over the last PERIOD against the PERIOD before, with a weekly series.
    def metric(items, format:, polarity:, at: nil, &value)
      time = ->(item) { at ? item.public_send(at) : item }
      within = ->(from, to) { items.select { time.call(_1) > from && time.call(_1) <= to } }
      series = Array.new((WINDOW / BUCKET).to_i) do |index|
        to = @now - (WINDOW - (BUCKET * (index + 1)))
        yield(within.call(to - BUCKET, to))
      end
      Reports::Metric.new(value: yield(within.call(@now - PERIOD, @now)), previous: yield(within.call(@now - (2 * PERIOD), @now - PERIOD)),
                          format: format, polarity: polarity, series: series)
    end

    def median(values)
      return if values.empty?

      sorted = values.sort
      middle = sorted.size / 2
      (sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0).round(1)
    end
  end
end
