# frozen_string_literal: true

# A run's compact status card in its own frame: the banner on the scenarios
# page while a run goes, and a Try's result under the scenario form. While
# the run is active, frame-poll reloads the frame from the run's page
# (RunsController#show answers a frame request with this alone); once it
# has finished, the new content stops polling.
class Views::Assistant::Evals::RunPanel < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  def self.frame_id(run) = "eval-run-#{run.id}"

  def initialize(run:)
    @run = run
  end

  def view_template
    turbo_frame_tag(self.class.frame_id(@run), target: "_top") do
      div(class: "report-frame",
          data: { controller: "frame-poll", frame_poll_active_value: @run.active?, frame_poll_url_value: assistant_evals_run_path(@run.id, compact: 1) }) do
        render Views::Assistant::Evals::RunStatusCard.new(run: @run, compact: true)
      end
    end
  end
end
