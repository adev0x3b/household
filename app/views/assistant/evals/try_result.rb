# frozen_string_literal: true

# A Try's run under the scenario form: its RunPanel, brought into view as it
# appears, since the button is in the form's sticky footer and the result
# below the form, out of sight on a phone. The panel polls inside; the wrapper stays,
# so the page scrolls once per Try.
class Views::Assistant::Evals::TryResult < Views::Base
  def initialize(run:)
    @run = run
  end

  def view_template
    div(data: { controller: "reveal" }) { render Views::Assistant::Evals::RunPanel.new(run: @run) }
  end
end
