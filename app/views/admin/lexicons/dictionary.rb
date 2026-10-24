# frozen_string_literal: true

# The dictionary check, which involves no model: each confirmed case's
# picks both ways, the wrong ones first.
class Views::Admin::Lexicons::Dictionary < Views::Admin::Lexicons::Part
  LOOKS = {
    "found" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "wrong" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    "missed" => Components::StatusLook.new(tone: :warning, icon: "fa-circle-question")
  }.freeze
  ORDER = { "wrong" => 0, "missed" => 1 }.freeze

  # report: the import's dictionary check (Lexicon::DictionaryCheck::Report).
  def initialize(import:, report:)
    @import = import
    @report = report
  end

  def render? = @report.any?

  def view_template
    result = -> do
      render Views::Admin::Lexicons::StatusBadge.new(status: @report.passed? ? "active" : "failed",
                                                     label: t("admin.lexicons.agent.statuses.#{@report.status}"))
    end
    section(@import.id, "dictionary", title: t("admin.lexicons.dictionary.title"), open: !@report.passed?, result: result) do
      p { @report.detail } if @report.detail.present?
      p(class: "report-hint") { t("admin.lexicons.dictionary.hint", rate: (Lexicon::DictionaryCheck::FOUND_AT_LEAST * 100).round) }
      picks if @report.results.any?
    end
  end

  private

  def picks
    div(class: "report-table-wrap") do
      table(class: "report-table lexicons__grid lexicons__grid--picks") do
        thead do
          tr do
            %w[said supplies expected got].each { |column| th(scope: "col") { t("admin.lexicons.dictionary.columns.#{column}") } }
          end
        end
        tbody { @report.results.sort_by { ORDER.fetch(_1.verdict, 2) }.each { |pick| row(pick) } }
      end
    end
  end

  def row(pick)
    tr do
      td { pick.said }
      td { pick.supplies.join(", ") }
      td { pick.expected }
      td do
        render LOOKS.fetch(pick.verdict).mark(label: t("admin.lexicons.dictionary.verdicts.#{pick.verdict}"))
        plain " #{pick.got || "–"}"
      end
    end
  end
end
