# frozen_string_literal: true

module Reports
  module Finance
    # What the Finance page reads, one instance per request. Each report is
    # built the first time it is read, and every one of them reads the
    # page's one Window, so the page loads its series and days once.
    class Dashboard
      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @audience = audience
        @period = period
        @today = today
        @window = window
      end

      def spending
        @spending ||= Spending.new(audience: @audience, period: @period, window: @window)
      end

      def income
        @income ||= Income.new(audience: @audience, period: @period, window: @window)
      end

      def cash_flow
        @cash_flow ||= CashFlow.new(audience: @audience, period: @period, window: @window)
      end

      def settlements
        @settlements ||= Settlements.new(audience: @audience, period: @period)
      end

      def attention
        @attention ||= AttentionItems.new(audience: @audience, today: @today, window: @window)
      end
    end
  end
end
