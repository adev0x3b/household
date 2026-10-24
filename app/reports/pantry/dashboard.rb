# frozen_string_literal: true

module Reports
  module Pantry
    # What the Pantry & meals page reads, one instance per request. Each
    # report is built the first time it is read, and every one of them
    # reads the page's one Window.
    class Dashboard
      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @audience = audience
        @period = period
        @today = today
        @window = window
      end

      def meals
        @meals ||= Meals.new(period: @period, today: @today, window: @window)
      end

      def groceries
        @groceries ||= Groceries.new(audience: @audience, period: @period, window: @window)
      end

      def attention
        @attention ||= AttentionItems.new(meals: meals, today: @today, window: @window)
      end
    end
  end
end
