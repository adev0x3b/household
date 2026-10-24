# frozen_string_literal: true

# A run's results as one bar: the share that passed, failed and hit an
# error (not scored), each in its tone. An image to assistive technology,
# named by `label`; the numbers are always written next to it.
class Views::Assistant::Evals::RateBar < Views::Base
  def initialize(run:, label:)
    @run = run
    @label = label
  end

  def view_template
    return if @run.done.zero?

    div(class: "eval-rate-bar", role: "img", aria: { label: @label }) do
      part(:good, @run.passed)
      part(:critical, @run.scored - @run.passed)
      part(:warning, @run.errors)
    end
  end

  private

  # flex-grow carries the share, so the bar needs no inline style.
  def part(tone, count)
    return unless count.positive?

    span(class: "eval-rate-bar__part eval-rate-bar__part--#{tone}", data: { share: share(count) })
  end

  # Tenths of the bar, at least one: a single failure in sixty still shows.
  def share(count) = [ (count * 10.0 / @run.done).round, 1 ].max
end
