# frozen_string_literal: true

module Reports
  module Agenda
    # What the Agenda page reads, one instance per request: tasks, and the
    # appointments that aren't medical. Each report is built the first time
    # it is read, and every one of them reads the page's one Window.
    class Dashboard
      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @period = period
        @today = today
        @window = window
      end

      def tasks
        @tasks ||= Tasks.new(period: @period, today: @today, window: @window)
      end

      def appointments
        @appointments ||= Appointments.new(period: @period, today: @today, window: @window)
      end

      def attention
        @attention ||= AttentionItems.new(today: @today, window: @window)
      end
    end
  end
end
