# frozen_string_literal: true

module Reports
  module Healthcare
    # What the Healthcare page reads, one instance per request. Each report
    # is built the first time it is read, and every one of them reads the
    # page's one Window, so the page loads its series and days once.
    class Dashboard
      # `now` is the moment a dose is judged overdue from.
      def initialize(audience:, period:, today: Date.current, now: Time.current, window: Window.new(audience))
        @audience = audience
        @period = period
        @today = today
        @now = now
        @window = window
      end

      def medications
        @medications ||= Medications.new(audience: @audience, period: @period, today: @today, window: @window)
      end

      def appointments
        @appointments ||= Appointments.new(audience: @audience, period: @period, today: @today, window: @window)
      end

      def spending
        @spending ||= Spending.new(audience: @audience, period: @period, today: @today, window: @window)
      end

      def labs
        @labs ||= Labs.new(audience: @audience, period: @period, today: @today)
      end

      def supplies
        @supplies ||= Supplies.new(audience: @audience, today: @today)
      end

      def attention
        @attention ||= AttentionItems.new(
          audience: @audience, supplies: supplies, labs: labs, today: @today, now: @now, window: @window,
        )
      end
    end
  end
end
