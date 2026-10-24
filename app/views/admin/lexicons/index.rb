# frozen_string_literal: true

# One row per language: what's active, how the last attempt went, and
# Import on the row itself.
class Views::Admin::Lexicons::Index < Views::Base
  include Phlex::Rails::Helpers::NumberWithDelimiter

  def initialize(languages:, imports:, problems:)
    @languages = languages
    @imports = imports
    @problems = problems
  end

  def page_title = t("admin.lexicons.index.title")

  def navbar_controls
    Components::PageControls.new(actions: [
                                   Components::Action.new(href: routes.new_admin_lexicon_path, icon: "fa-plus", label: t("admin.lexicons.add.title"),
                                                          turbo_stream: true)
                                 ])
  end

  def view_template
    div(class: "report-page lexicons") do
      render Components::PageHeader.new(title: t("admin.lexicons.index.title"))
      p(class: "report-hint") { t("admin.lexicons.index.hint") }
      problems if @problems.any?
      ul(class: "lexicons__list") { @languages.each { |language| row(language) } }
      render Views::Admin::Lexicons::Attribution.new
    end
  end

  private

  def problems
    render Components::Notice.new(tone: :critical) do
      p { t("admin.lexicons.index.problems") }
      ul { @problems.each { |problem| li { problem } } }
    end
  end

  def row(language)
    imports = Array(@imports[language.code])
    active = imports.find(&:active?)
    last = imports.first
    li(class: "lexicons__row") do
      a(href: admin_lexicon_path(language.code), class: "lexicons__name") do
        span(class: "lexicons__code") { language.code }
        plain " #{language.wiktionary}"
        span(class: "report-tag") { t("admin.lexicons.pivot") } if language.pivot?
      end
      div(class: "lexicons__facts") do
        render Views::Admin::Lexicons::StatusBadge.new(status: last&.status)
        span { active ? t("admin.lexicons.nouns", count: active.lemma_count, formatted: number_with_delimiter(active.lemma_count)) : t("admin.lexicons.not_imported") }
        span { t("admin.lexicons.source_of", date: l(active.source_last_modified.to_date, format: :long)) } if active&.source_last_modified
      end
      failure(last) if last&.failed?
      div(class: "lexicons__actions") do
        render Components::ItemAction.new(href: new_admin_lexicon_import_path(language.code), icon: "fa-cloud-arrow-down", turbo_stream: true,
                                          label: t("admin.lexicons.import", language: language.wiktionary))
      end
    end
  end

  def failure(import)
    p(class: "lexicons__failure") do
      strong { t("admin.lexicons.failed_at", step: t("admin.lexicons.steps.#{import.failed_step}", default: import.failed_step.to_s)) }
      plain " #{import.error.to_s.truncate(160)}"
    end
  end
end
