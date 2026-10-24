# frozen_string_literal: true

# The evals' Runs page: every run, newest first, one
# Views::Assistant::Evals::RunRow each.
class Views::Assistant::Evals::Runs::Index < Views::Base
  def initialize(runs:)
    @runs = runs
  end

  def page_title = t("assistant.evals.title")

  def view_template
    div(class: "report-page report-page--wide evals") do
      render Components::PageHeader.new(title: t("assistant.evals.title"))
      render Views::Assistant::Evals::Tabs.new(current: :runs)
      if @runs.empty?
        render Components::EmptyState.new(icon: "fa-clock-rotate-left", message: t("assistant.evals.empty.runs"))
      else
        section(class: "eval-runs", aria: { label: t("assistant.evals.tabs.runs") }) do
          ol(class: "report-rows eval-runs__list") { @runs.each { |run| render Views::Assistant::Evals::RunRow.new(run: run) } }
        end
        render Components::Pagination.new(collection: @runs)
      end
    end
  end
end
