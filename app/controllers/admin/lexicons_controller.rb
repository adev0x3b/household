# frozen_string_literal: true

# The lexicon's languages, each one's page with its import report and test
# cases, and adding one kaikki.org has, imported at once. What is done to
# an import is Admin::LexiconImportsController's, to a case Admin::LexiconCasesController's.
class Admin::LexiconsController < Admin::BaseController
  HISTORY = 10

  before_action :set_language, only: :show

  def index
    languages = LexiconLanguage.by_code.to_a
    imports = LexiconImport.where(language: languages.map(&:code)).latest_first.group_by(&:language)
    render_page Views::Admin::Lexicons::Index.new(languages: languages.map(&:to_config), imports: imports, problems: Lexicon::Config.problems)
  end

  # The active import's report first — it's what the assistant uses; a later
  # attempt (failed, waiting for review, running) is announced above it.
  # Earlier imports and the cases are paginated, each with its own page
  # param (history_page, cases_page).
  def show
    imports = LexiconImport.where(language: @language.code).latest_first
    history = imports.paginate(page: params[:history_page], per_page: HISTORY)
    active = LexiconImport.active_for(@language.code)
    latest = imports.first
    import = params[:import].present? ? imports.find(params[:import]) : (active || latest)
    render_page Views::Admin::Lexicons::Show.new(language: @language.to_config, import: import, history: history, latest: latest, active: active,
                                                 agent_report: Lexicon::AgentEval::Report.of(import),
                                                 dictionary_report: Lexicon::DictionaryCheck::Report.of(import),
                                                 cases: Lexicon::CaseList.new(@language, import: import, page: params[:cases_page]),
                                                 cases_page: params[:cases_page], worker_alive: Lexicon::Worker.alive?,
                                                 writing_cases: Lexicon::EvalCasesJob.writing?(@language), cases_error: @language.cases_error)
  end

  def new
    render_modal(Views::Admin::Lexicons::Modals::New.new(language: LexiconLanguage.new, catalog: catalog), page: admin_lexicons_path)
  end

  # The name picked from kaikki.org's list; its code is read from the start
  # of its extract (Lexicon::Source#peek), so nothing is typed but the name.
  def create
    given = params.expect(lexicon_language: %i[wiktionary head])
    result = Lexicon::AddLanguage.call(given[:wiktionary], head: given[:head])
    language = result.language
    if result.success?
      started = Lexicon::StartImport.call(language, by: current_profile)
      if started.success?
        toast_flash(:notice, t("admin.lexicons.notices.started", language: language.wiktionary))
      else
        toast_flash(:alert, started.import.error)
      end
      redirect_to admin_lexicon_path(language.code), status: :see_other
    else
      render turbo_stream: redraw_modal(Views::Admin::Lexicons::Modals::New.new(language: language, catalog: catalog)),
             status: :unprocessable_content
    end
  end

  private

  def set_language
    @language = LexiconLanguage.find_by!(code: params[:language])
  end

  # kaikki.org's languages not added yet.
  def catalog
    added = LexiconLanguage.pluck(:wiktionary).to_set
    Lexicon::Catalog.languages.reject { |entry| added.include?(entry.name) }
  end
end
