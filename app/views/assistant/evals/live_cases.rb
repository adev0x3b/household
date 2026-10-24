# frozen_string_literal: true

# Every scenario run of an eval, in order, with its state; each links to
# its part of the timeline.
class Views::Assistant::Evals::LiveCases < Views::Base
  def initialize(events:)
    @events = events
  end

  def view_template
    ol(id: "eval-cases", class: "eval-cases") do
      @events.cases.each { |kase| render Views::Assistant::Evals::LiveCase.new(kase: kase) }
    end
  end
end
