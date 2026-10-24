# frozen_string_literal: true

# The language's test cases, ten to a page, those waiting for the admin
# first; each is confirmed or fixed on its row, and the admin's own can be
# deleted.
class Views::Admin::Lexicons::Cases < Views::Admin::Lexicons::Part
  # list: the language's cases as the page lists them (Lexicon::CaseList).
  # writing: the model is writing them again; error: why it couldn't, the
  # last time.
  def initialize(language:, import:, list:, writing:, error:)
    @language = language
    @import = import
    @list = list
    @writing = writing
    @error = error
  end

  def view_template
    unconfirmed = @list.unconfirmed_count
    result = -> do
      if @list.empty? then plain t("admin.lexicons.show.cases_none")
      elsif unconfirmed.positive? then span(class: "report-flag") { t("admin.lexicons.show.cases_to_confirm", count: unconfirmed) }
      else plain t("admin.lexicons.show.cases_all_confirmed", count: @list.size)
      end
    end
    open = @list.empty? || unconfirmed.positive? || @writing || @error.present?
    section(@import&.id || @language.code, "cases", title: t("admin.lexicons.cases.title"), open: open, result: result) do
      div(class: "lexicons__cases-head") do
        p(class: "report-hint") { t("admin.lexicons.cases.hint") }
        render Components::ItemAction.new(href: new_admin_lexicon_case_path(@language.code, page_param), icon: "fa-plus", turbo_stream: true,
                                          label: t("admin.lexicons.cases.new"))
      end
      p(class: "report-hint") { t("admin.lexicons.cases.writing") } if @writing
      p(class: "lexicons__failure") { t("admin.lexicons.cases.error", error: @error) } if @error
      if @list.empty?
        p(class: "report-hint") { t("admin.lexicons.cases.none") }
      else
        ul(class: "lexicons__cases") { @list.shown.each { |kase| row(kase) } }
        render Components::Pagination.new(collection: @list.shown, turbo_frame: "lexicon-import", turbo_action: "advance", param_name: :cases_page)
      end
    end
  end

  private

  # Keeps the admin on their page of cases across a confirm, a fix, a delete.
  def page_param = { cases_page: (@list.shown.current_page if @list.shown.current_page > 1) }

  def row(kase)
    reason = @list.reason(kase)
    li(class: "lexicons__case#{" lexicons__case--confirmed" if kase.confirmed?}") do
      div(class: "lexicons__case-body") do
        p(class: "lexicons__case-title") do
          strong { kase.concept }
          plain " → #{kase.native_singular} / #{kase.native_plural}"
          if kase.confirmed?
            span(class: "report-tag") { t("admin.lexicons.cases.confirmed") }
          else
            span(class: "report-flag") { t("admin.lexicons.cases.reasons.#{reason || :unconfirmed}", language: @language.wiktionary) }
          end
          span(class: "report-flag") { t("admin.lexicons.cases.reasons.duplicate") } if reason == :duplicate
          span(class: "report-tag") { t("admin.lexicons.cases.own") } if @list.own?(kase)
        end
        p(class: "lexicons__case-sentence") { kase.dose_sentence }
        p(class: "lexicons__case-sentence") { kase.purchase_sentence }
      end
      div(class: "lexicons__case-actions") { actions(kase) }
    end
  end

  def actions(kase)
    unless kase.confirmed?
      render Components::ItemAction.new(href: confirm_admin_lexicon_case_path(@language.code, kase, page_param), icon: "fa-check", method: :patch,
                                        label: t("admin.lexicons.cases.confirm", concept: kase.concept))
    end
    render Components::ItemAction.new(href: edit_admin_lexicon_case_path(@language.code, kase, page_param), icon: "fa-pen", turbo_stream: true,
                                      label: t("admin.lexicons.cases.edit", concept: kase.concept))
    return unless @list.own?(kase)

    render Components::ItemAction.new(href: admin_lexicon_case_path(@language.code, kase, page_param), icon: "fa-trash", method: :delete,
                                      label: t("admin.lexicons.cases.destroy", concept: kase.concept), danger: true,
                                      confirm: t("admin.lexicons.cases.destroy_confirm", concept: kase.concept))
  end
end
