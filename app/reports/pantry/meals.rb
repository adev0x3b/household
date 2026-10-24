# frozen_string_literal: true

module Reports
  module Pantry
    # The meals planned and eaten, each day from one OccurrenceLedger:
    # whether the plan was followed over the period, and, as of today
    # whatever period is selected, the meals planned for today and the next
    # 7 days and those short on ingredients.
    class Meals
      # Status colors carry meaning here and the legend names them, as in
      # Healthcare::Appointments::STATUS_SERIES.
      OUTCOME_SERIES = { eaten: "good", not_eaten: "critical", upcoming: "series-1" }.freeze

      ShortRow = Data.define(:date, :title, :missing, :occurrence)
      MealTypeRow = Data.define(:meal_type, :due, :eaten, :rate)

      def initialize(period:, today:, window:)
        @period = period
        @today = today
        @window = window
      end

      def any? = period_entries.any?

      def planned_metric
        Metric.new(value: planned_entries.size, format: :count, polarity: :neutral)
      end

      def eaten_metric
        Metric.new(value: rate(@period), previous: rate(@period.previous), format: :percent, polarity: :higher_is_better)
      end

      # Planned home-cooked meals whose recipes need more than is on the
      # shelf of whoever cooks (the meal's owner, like the calendar's
      # warning). Each cook's shelf is read once, however many meals they
      # plan.
      def short_rows
        @short_rows ||= begin
          shelves = Hash.new { |held, profile| held[profile] = ::Pantry::Availability.new(profile) }
          planned_entries.filter_map do |entry|
            details = entry.details
            next unless details.home?

            missing = shelves[entry.event.profile].for(details.resolved_recipes).select(&:short?)
              .map { |line| line.recipe_ingredient.ingredient.name }.uniq
            next if missing.empty?

            ShortRow.new(date: entry.date, title: entry.label, missing: missing, occurrence: entry.occurrence)
          end
        end
      end

      # Eaten, not eaten and still-to-come meals per bucket of the period.
      def outcomes_chart
        by_bucket = @period.per_bucket(period_entries.reject(&:cancelled?), &:date)

        Chart.new(
          kind: :stacked_bar, title: I18n.t("home.pantry.meals.chart"),
          labels: @period.bucket_labels,
          series: OUTCOME_SERIES.map do |outcome, color|
            values = by_bucket.map { |entries| entries.count { |entry| outcome(entry) == outcome } }
            Chart::Series.new(label: I18n.t("home.pantry.meals.outcomes.#{outcome}"), values: values, color: color)
          end,
        )
      end

      # How well each kind of meal (breakfast, lunch…) follows the plan.
      def meal_type_rows
        types = Meal::Details.meal_types
        period_entries.select(&:due?).group_by { |entry| entry.details.meal_type }.map do |meal_type, entries|
          MealTypeRow.new(meal_type: meal_type, due: entries.size, eaten: entries.count(&:taken?), rate: OccurrenceLedger.rate(entries))
        end.sort_by { |row| types.fetch(row.meal_type, types.size) }
      end

      private

      def entries
        @entries ||= begin
          span = Period.new(
            start_date: [ @period.previous.start_date, @today ].min, end_date: [ @period.end_date, Period.ahead(today: @today).end_date ].max,
          )
          @window.ledger(span, today: @today, of: Meal).entries
        end
      end

      def entries_in(period) = entries.select { |entry| period.range.cover?(entry.date) }

      def period_entries
        @period_entries ||= entries_in(@period)
      end

      def rate(period) = OccurrenceLedger.rate(entries_in(period))

      def planned_entries
        @planned_entries ||= entries_in(Period.from_today(today: @today)).select(&:to_come?)
      end

      def outcome(entry)
        if entry.taken? then :eaten
        elsif entry.to_come? then :upcoming
        else :not_eaten
        end
      end
    end
  end
end
