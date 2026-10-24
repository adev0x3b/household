# frozen_string_literal: true

# One scenario run in the tracker's list, queued, running, passed, failed
# or in error (not scored): an icon in its tone, and the word for screen
# readers.
class Views::Assistant::Evals::LiveCase < Views::Base
  def initialize(kase:)
    @kase = kase
  end

  def view_template
    li(id: "eval-case-#{@kase["index"]}", class: "eval-case eval-case--#{@kase["state"]}") do
      a(href: "#eval-scenario-#{@kase["index"]}", class: "eval-case__link") do
        render Views::Assistant::Evals::Status.scenario(@kase["state"]).mark
        # A zero-width space after each underscore: the narrow list breaks a long name there, not mid-word.
        span(class: "eval-case__name") { t("assistant.evals.live.case_label", scenario: @kase["scenario"].to_s.gsub("_", "_\u200B"), rep: @kase["rep"]) }
        span(class: "is-sr-only") { t("assistant.evals.live.states.#{@kase["state"]}") }
      end
    end
  end
end
