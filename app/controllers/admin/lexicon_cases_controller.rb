# frozen_string_literal: true

# A language's test cases on the admin page: written again by the model,
# then each fixed by hand, confirmed as written, or added for a supply of
# the admin's own. A case a person vouched for counts in the import's
# checks and is kept when the cases are written again (Lexicon::EvalCases).
class Admin::LexiconCasesController < Admin::BaseController
  FIELDS = %i[native_singular native_plural dose_sentence purchase_sentence].freeze

  before_action :set_language
  before_action :set_case, only: %i[edit update confirm destroy]

  def new
    @case = @language.lexicon_eval_cases.new
    render_modal(form, page: back_to_page)
  end

  def create
    @case = @language.lexicon_eval_cases.new(params.expect(lexicon_eval_case: [ :concept, :english_plural, *FIELDS ]).merge(confirmed: true))
    if @case.save
      toast_flash(:success, t("admin.lexicons.cases.created", concept: @case.concept))
      redirect_to back_to_page, status: :see_other
    else
      render turbo_stream: redraw_modal(form), status: :unprocessable_content
    end
  end

  def edit
    render_modal(form, page: back_to_page)
  end

  def update
    if @case.update(params.expect(lexicon_eval_case: FIELDS).merge(confirmed: true))
      toast_flash(:success, t("admin.lexicons.cases.saved", concept: @case.concept))
      redirect_to back_to_page, status: :see_other
    else
      render turbo_stream: redraw_modal(form), status: :unprocessable_content
    end
  end

  def confirm
    @case.update!(confirmed: true)
    toast_flash(:success, t("admin.lexicons.cases.confirmed_notice", concept: @case.concept))
    redirect_to back_to_page, status: :see_other
  end

  # The shared cases can't be deleted: writing the cases again would bring them back.
  def destroy
    if @case.shared?
      toast_flash(:alert, t("admin.lexicons.cases.shared", concept: @case.concept))
    else
      @case.destroy!
      toast_flash(:success, t("admin.lexicons.cases.destroyed", concept: @case.concept))
    end
    redirect_to back_to_page, status: :see_other
  end

  def write
    Lexicon::EvalCasesJob.start(@language, by: current_profile) unless Lexicon::EvalCasesJob.writing?(@language)
    toast_flash(:notice, t("admin.lexicons.notices.writing_cases", language: @language.wiktionary))
    redirect_to back_to_page, status: :see_other
  end

  private

  def set_language
    @language = LexiconLanguage.find_by!(code: params[:lexicon_language])
  end

  def set_case
    @case = @language.lexicon_eval_cases.find(params[:id])
  end

  # The language's page, on the page of cases the admin was reading.
  def back_to_page = admin_lexicon_path(@language.code, cases_page: params[:cases_page].presence)

  def form
    page = { cases_page: params[:cases_page].presence }
    url = @case.new_record? ? admin_lexicon_cases_path(@language.code, page) : admin_lexicon_case_path(@language.code, @case, page)
    Views::Admin::Lexicons::Modals::Case.new(kase: @case, url: url, language: @language, examples: examples,
                                             concepts: (Lexicon::EvalCases.missing_concepts(@language) if @case.new_record?))
  end

  # The English sentences the case's two translate, about its supply: an
  # ellipsis stands in for one not named yet.
  def examples
    item = @case.english_plural.presence || (@case.concept.present? ? Lexicon::EvalCases.english_plural(@case) : "…")
    { dose_sentence: Lexicon::EvalCases.dose_message(item), purchase_sentence: Lexicon::EvalCases.purchase_message(item) }
  end
end
