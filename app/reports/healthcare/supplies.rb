# frozen_string_literal: true

module Reports
  module Healthcare
    # How long current stock lasts and which batches expire soon. Always as
    # of today, never scoped to the period: a runway is forward-looking by
    # definition.
    #
    #   days left = remaining stock ÷ daily rate (Supply.daily_rates: the
    #               recurring schedule when there is one, else the last 30
    #               days of use). No rate means no estimate, not "forever".
    #   severity  = :critical at ≤ 14 days or under the low-stock threshold,
    #               :warning at ≤ 30 days, otherwise :good
    class Supplies
      CRITICAL_DAYS = 14
      WARNING_DAYS = 30
      EXPIRY_HORIZON_DAYS = 30
      CHART_LIMIT = 10

      SEVERITY_TOKENS = { critical: "critical", warning: "warning", good: "good" }.freeze

      RunwayRow = Data.define(:supply, :remaining, :days_left, :low_stock) do
        def depletion_date(today = Date.current) = days_left && (today + days_left)

        def severity
          return :critical if low_stock || (days_left && days_left <= CRITICAL_DAYS)
          return :warning if days_left && days_left <= WARNING_DAYS

          days_left ? :good : :unknown
        end
      end

      ExpiringRow = Data.define(:purchase, :supply, :expires_on, :remaining) do
        def expired?(today = Date.current) = expires_on < today
      end

      def initialize(audience:, today: Date.current)
        @audience = audience
        @today = today
      end

      def any? = runway_rows.any?

      def runway_rows
        @runway_rows ||= begin
          supplies = Supply.where(id: @audience.supply_purchases.select(:supply_id)).to_a
          remaining = @audience.supply_purchases.where("quantity_remaining > 0").group(:supply_id).sum(:quantity_remaining)
          rates = Supply.daily_rates(supplies)

          supplies.map do |supply|
            left = remaining.fetch(supply.id, 0)
            rate = rates[supply.id]
            RunwayRow.new(
              supply: supply, remaining: left,
              days_left: rate&.positive? ? (left / rate).floor : nil,
              low_stock: supply.low_stock_threshold.present? && left <= supply.low_stock_threshold,
            )
          end.sort_by { |row| [ row.days_left || Float::INFINITY, row.supply.name.downcase ] }
        end
      end

      def attention_rows = runway_rows.select { |row| row.severity == :critical }

      def runway_chart
        rows = runway_rows.select(&:days_left).first(CHART_LIMIT)

        Chart.new(
          kind: :horizontal_bar, title: I18n.t("home.healthcare.supplies.runway_chart"), format: :days,
          labels: rows.map { |row| row.supply.name },
          series: [
            Chart::Series.new(
              label: I18n.t("home.healthcare.supplies.days_left"), values: rows.map(&:days_left),
              colors: rows.map { |row| SEVERITY_TOKENS.fetch(row.severity) },
            )
          ],
        )
      end

      def expiring_rows
        @expiring_rows ||= @audience.supply_purchases.where("quantity_remaining > 0").includes(:supply)
          .filter_map do |purchase|
            expires_on = purchase.effective_expiration_date
            next unless expires_on && expires_on <= @today + EXPIRY_HORIZON_DAYS

            ExpiringRow.new(purchase: purchase, supply: purchase.supply, expires_on: expires_on, remaining: purchase.quantity_remaining)
          end
          .sort_by(&:expires_on)
      end
    end
  end
end
