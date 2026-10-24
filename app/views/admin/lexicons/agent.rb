# frozen_string_literal: true

# The assistant tests: a supply × scenario grid, the English-only controls
# beside the language's, and each failure with what the assistant called.
class Views::Admin::Lexicons::Agent < Views::Admin::Lexicons::Part
  LOOKS = {
    "passed" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    "error" => Components::StatusLook.new(tone: :warning, icon: "fa-triangle-exclamation")
  }.freeze
  # The import's statuses that wear the tests' outcome.
  STATUSES = { "passed" => "active", "failed" => "failed", "running" => "running" }.freeze

  # report: the import's assistant tests (Lexicon::AgentEval::Report).
  def initialize(import:, language:, report:)
    @import = import
    @language = language
    @report = report
  end

  def render? = @report.any?

  def view_template
    section(@import.id, "agent", title: t("admin.lexicons.agent.title"), open: !@report.passed?, result: -> { result }) do
      p { @report.detail } if @report.detail.present?
      p(class: "report-hint") { t("admin.lexicons.agent.hint", tolerance: (Lexicon::AgentEval::TOLERANCE * 100).round) }
      if @report.results.any?
        grid
        failures
      end
    end
  end

  private

  def result
    render Views::Admin::Lexicons::StatusBadge.new(status: STATUSES.fetch(@report.status, "none"),
                                                   label: t("admin.lexicons.agent.statuses.#{@report.status.presence || "none"}"))
    span(class: "report-tag") { t("admin.lexicons.agent.rerun_badge") } if @report.rerun
    plain " #{t("admin.lexicons.show.agent_passed", passed: @report.passed, scored: @report.scored)}" if @report.scored
  end

  # One row per concept (and per language, for the pivot's), one column per kind of scenario.
  def grid
    rows = @report.results.group_by { [ _1.code, _1.concept ] }
    div(class: "report-table-wrap") do
      table(class: "report-table lexicons__grid") do
        thead do
          tr do
            th(scope: "col") { t("admin.lexicons.agent.concept") }
            Lexicon::AgentEval::ALL_KINDS.each { |kind| th(scope: "col", class: control_class(kind)) { t("admin.lexicons.agent.kinds.#{kind}") } }
          end
        end
        tbody do
          rows.each do |(code, concept), results|
            tr do
              th(scope: "row") { named(code, concept) }
              Lexicon::AgentEval::ALL_KINDS.each { |kind| td(class: control_class(kind)) { icon(results.find { _1.kind == kind }) } }
            end
          end
        end
      end
    end
  end

  def icon(result)
    return plain("–") unless result

    render LOOKS.fetch(result.status).mark(label: t("admin.lexicons.agent.result_statuses.#{result.status}"), title: result.reason)
  end

  def failures
    failing = @report.failing
    return if failing.empty?

    h3(class: "lexicons__minor") { t("admin.lexicons.agent.failures", count: failing.size) }
    ul(class: "lexicons__failures") do
      failing.each do |result|
        li do
          strong { "#{named(result.code, result.concept)} · #{t("admin.lexicons.agent.kinds.#{result.kind}")}" }
          result.failures.each { |failure| p(class: "lexicons__failure-text") { failure } }
          p(class: "lexicons__failure-text") { result.error } if result.error.present?
          p(class: "lexicons__tools") { t("admin.lexicons.agent.tools", tools: result.tools.presence || "–") }
        end
      end
    end
  end

  # The language's own concepts plainly; another language's (the pivot's tests) with its code.
  def named(code, concept) = code == @language.code ? concept : "#{concept} (#{code})"

  def control_class(kind) = ("lexicons__control" if kind.control?)
end
