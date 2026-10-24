# frozen_string_literal: true

# The evals' three pages: the overview (how the assistant is doing), the
# scenarios (what it is tested on) and the runs (every time it was).
class Views::Assistant::Evals::Tabs < Views::Base
  def initialize(current:)
    @current = current
  end

  def view_template
    render Components::Tabs.new(label: t("assistant.evals.tabs.label"), current: @current, items: [
                                  Components::NavItem.new(key: :overview, icon: "fa-gauge-high", href: assistant_evals_path,
                                                          label: t("assistant.evals.tabs.overview")),
                                  Components::NavItem.new(key: :scenarios, icon: "fa-list-check", href: assistant_evals_scenarios_path,
                                                          label: t("assistant.evals.tabs.scenarios")),
                                  Components::NavItem.new(key: :runs, icon: "fa-clock-rotate-left", href: assistant_evals_runs_path,
                                                          label: t("assistant.evals.tabs.runs"))
                                ])
  end
end
