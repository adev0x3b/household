# frozen_string_literal: true

module Reports
  # "Needs attention" across sections: the items each section's dashboard
  # already reports (Reports::Agenda::AttentionItems and the others), merged
  # and sorted the way each section sorts its own: most urgent first, then
  # the nearest to today (Reports::AttentionItem.sorted).
  class AttentionItems
    include Enumerable

    def initialize(*sources, today: Date.current)
      @sources = sources
      @today = today
    end

    def each(&block) = items.each(&block)

    def items
      @items ||= AttentionItem.sorted(@sources.flat_map(&:to_a), today: @today)
    end
  end
end
