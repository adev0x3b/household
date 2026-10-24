# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A task: a title and its day, nothing beyond what every series has.
    class Tasks < Series
      # A task said again within a few days is most likely the same one.
      DUPLICATE_WINDOW = 3

      private

      def duplicate_window = DUPLICATE_WINDOW
    end
  end
end
