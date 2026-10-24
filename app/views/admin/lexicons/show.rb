# frozen_string_literal: true

# A language's page: the import shown, as one status card and a section per
# part of its report, each saying its result in its header, then the
# language's test cases and its earlier imports. A section that failed, runs
# or waits for the admin starts open; the page reloads itself while
# something runs (frame-poll).
class Views::Admin::Lexicons::Show < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  # history: a page of the language's imports (will_paginate). reports: the
  # import's assistant tests and dictionary check, read from its report
  # (Lexicon::AgentEval::Report, Lexicon::DictionaryCheck::Report). cases:
  # the language's test cases as listed (Lexicon::CaseList), on the page
  # cases_page asked for.
  def initialize(language:, import:, history:, active:, agent_report:, dictionary_report:, cases:, cases_page: nil, latest: nil,
                 worker_alive: nil, writing_cases: false, cases_error: nil)
    @language = language
    @import = import
    @history = history
    @active = active
    @agent_report = agent_report
    @dictionary_report = dictionary_report
    @cases = cases
    @cases_page = cases_page
    @latest = latest
    @worker_alive = worker_alive
    @writing_cases = writing_cases
    @cases_error = cases_error
  end

  def page_title = "#{@language.wiktionary} (#{@language.code})"

  # Import always; going on with or stopping the newest attempt while it
  # waits or runs; the assistant tests again once one is active; the cases
  # written again for any language but the pivot, which has none.
  def navbar_controls
    code = @language.code
    actions = []
    if @latest&.running? || @latest&.awaiting_review?
      actions << Components::Action.new(href: routes.cancel_admin_lexicon_import_path(code, @latest), icon: "fa-stop", method: :post,
                                        label: t("admin.lexicons.cancel"), confirm: t("admin.lexicons.cancel_confirm", language: @language.wiktionary))
    end
    if @latest&.awaiting_review?
      actions << Components::Action.new(href: routes.resume_admin_lexicon_import_path(code, @latest), icon: "fa-forward", method: :post,
                                        label: t("admin.lexicons.continue"))
    end
    actions << Components::Action.new(href: routes.new_admin_lexicon_import_path(code), icon: "fa-cloud-arrow-down", turbo_stream: true,
                                      label: t("admin.lexicons.import", language: @language.wiktionary))
    if @active
      actions << Components::Action.new(href: routes.evaluate_admin_lexicon_import_path(code, @active), icon: "fa-vial-circle-check", method: :post,
                                        label: t("admin.lexicons.agent.rerun"), confirm: t("admin.lexicons.agent.rerun_confirm"))
    end
    unless @language.pivot?
      actions << Components::Action.new(href: routes.write_admin_lexicon_cases_path(code), icon: "fa-wand-magic-sparkles", method: :post,
                                        label: t("admin.lexicons.cases.write"), confirm: t("admin.lexicons.cases.write_confirm"))
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "report-page lexicons") do
      render Components::PageHeader.new(title: page_title, back_href: admin_lexicons_path, back_label: t("admin.lexicons.show.back"))
      turbo_frame_tag("lexicon-import", target: "_top") do
        div(class: "report-frame", data: { controller: "frame-poll", frame_poll_active_value: busy?,
                                           frame_poll_url_value: admin_lexicon_path(@language.code, import: @import&.id, cases_page: @cases_page.presence) }) do
          report
        end
      end
      render Views::Admin::Lexicons::History.new(language: @language, import: @import, history: @history)
      render Views::Admin::Lexicons::Attribution.new
    end
  end

  private

  def report
    newer_attempt
    awaiting_banner if @import&.awaiting_review?
    render Views::Admin::Lexicons::StatusCard.new(import: @import, worker_alive: @worker_alive)
    render Views::Admin::Lexicons::Steps.new(import: @import) if @import
    render Views::Admin::Lexicons::Dictionary.new(import: @import, report: @dictionary_report)
    render Views::Admin::Lexicons::Agent.new(import: @import, language: @language, report: @agent_report)
    return if @language.pivot?

    render Views::Admin::Lexicons::Cases.new(language: @language, import: @import, list: @cases, writing: @writing_cases, error: @cases_error)
  end

  def busy? = @import&.running? || @latest&.running? || @agent_report.running? || @writing_cases || false

  # A later attempt than the one shown (failed, waiting, running): say so, with a link.
  def newer_attempt
    return unless @latest && @import && @latest != @import && @latest.created_at > @import.created_at

    render Components::Notice.new do
      plain t("admin.lexicons.show.newer_attempt", time: l(@latest.created_at, format: :short))
      whitespace
      render Views::Admin::Lexicons::StatusBadge.new(status: @latest.status)
      whitespace
      a(href: admin_lexicon_path(@language.code, import: @latest.id)) { t("admin.lexicons.show.see_it") }
    end
  end

  def awaiting_banner
    render Components::Notice.new(tone: :action) do
      p { t("admin.lexicons.review.banner", count: Lexicon::DictionaryCheck::MIN_CASES) }
    end
  end
end
