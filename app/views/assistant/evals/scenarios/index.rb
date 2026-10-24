# frozen_string_literal: true

# The evals' Scenarios page: what the assistant is tested on, filtered by
# tag. Each scenario's row says what it checks, its tags, and how it did in
# the last runs that played it (Views::Assistant::Evals::HistoryStrip).
# Tick scenarios and press Run in the navbar (the run modal's form takes
# the ticked boxes, `form="eval-run-form"`; Run waits while another run
# goes); each row can also be run alone, edited or deleted. A run in
# progress shows on top. New scenario is the navbar's too.
class Views::Assistant::Evals::Scenarios::Index < Views::Base
  def initialize(scenarios:, runs:, running:, tag: nil)
    @all_tags = scenarios.flat_map(&:tags).uniq.sort
    @tag = tag
    @scenarios = tag ? scenarios.select { |s| s.tags.include?(tag) } : scenarios
    @runs = runs
    @running = running
  end

  def page_title = t("assistant.evals.title")

  def navbar_controls
    actions = [ Components::Action.new(href: routes.new_assistant_evals_scenario_path, icon: "fa-plus", label: t("assistant.evals.new_scenario")) ]
    unless @running
      actions << Components::Action.new(href: routes.new_assistant_evals_run_path(tag: @tag), icon: "fa-play", turbo_stream: true,
                                        label: t("assistant.evals.run_button"))
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "report-page report-page--wide evals") do
      render Components::PageHeader.new(title: t("assistant.evals.title"))
      render Views::Assistant::Evals::Tabs.new(current: :scenarios)
      render Views::Assistant::Evals::RunPanel.new(run: @running) if @running
      tag_filter
      if @scenarios.empty?
        render Components::EmptyState.new(icon: "fa-list-check",
                                          message: @tag ? t("assistant.evals.empty.tagged", tag: @tag) : t("assistant.evals.empty.scenarios"))
      else
        list
      end
    end
  end

  private

  def tag_filter
    return if @all_tags.empty?

    nav(class: "eval-tags", aria: { label: t("assistant.evals.filter_by") }) do
      tag_link(nil, t("assistant.evals.all_tags"))
      @all_tags.each { |tag| tag_link(tag, tag) }
    end
  end

  def tag_link(tag, text)
    current = tag == @tag
    a(href: assistant_evals_scenarios_path(tag: tag), class: "eval-tags__tag#{" is-current" if current}",
      aria: { current: (current ? "page" : nil) }) { text }
  end

  def list
    section(class: "eval-scenarios", aria: { label: t("assistant.evals.tabs.scenarios") }) do
      p(class: "report-hint eval-scenarios__hint") { t("assistant.evals.select_hint", count: @scenarios.size) }
      ul(class: "eval-scenarios__list") { @scenarios.each { |scenario| row(scenario) } }
    end
  end

  def row(scenario)
    li(class: "eval-scenario") do
      input(type: "checkbox", name: "scenarios[]", value: scenario.name, form: "eval-run-form", class: "eval-scenario__select",
            aria: { label: t("assistant.evals.select_scenario", name: scenario.name) })
      div(class: "eval-scenario__main") do
        a(href: edit_assistant_evals_scenario_path(scenario.name), class: "eval-scenario__title", title: scenario.name) do
          number = scenario.name[/\A\d+/]
          span(class: "eval-scenario__number") { number } if number
          span { scenario.name.sub(/\A\d+_/, "").humanize }
        end
        p(class: "eval-scenario__description") { scenario.description } if scenario.description.present?
        if scenario.tags.any?
          span(class: "eval-scenario__tags") { scenario.tags.each { |tag| span(class: "report-tag") { tag } } }
        end
      end
      render Views::Assistant::Evals::HistoryStrip.new(scenario: scenario, runs: @runs)
      div(class: "eval-scenario__actions") { row_actions(scenario) }
    end
  end

  def row_actions(scenario)
    unless @running
      render Components::ItemAction.new(href: new_assistant_evals_run_path(only: scenario.name), icon: "fa-play", turbo_stream: true,
                                        label: t("assistant.evals.run_scenario", name: scenario.name))
    end
    render Components::ItemAction.new(href: edit_assistant_evals_scenario_path(scenario.name), icon: "fa-pen",
                                      label: t("assistant.evals.edit_scenario", name: scenario.name))
    render Components::ItemAction.new(href: assistant_evals_scenario_path(scenario.name), icon: "fa-trash", method: :delete, danger: true,
                                      label: t("assistant.evals.delete_scenario", name: scenario.name),
                                      confirm: t("assistant.evals.form.delete_confirm"))
  end
end
