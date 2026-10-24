# frozen_string_literal: true

# The model server went away mid-run (the task waits), came back, or didn't.
class Views::Assistant::Evals::Timeline::Outage < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(class: "eval-tl eval-tl--outage") do
      render Components::StatusLook.new(tone: :warning, icon: "fa-plug-circle-xmark").mark
      plain " #{text}"
    end
  end

  private

  def text
    if @event["type"] == "outage_started" then t("assistant.evals.live.outage_started", streak: @event["streak"])
    elsif @event["gave_up"] then t("assistant.evals.live.outage_gave_up")
    else t("assistant.evals.live.outage_ended", seconds: @event["waited"])
    end
  end
end
