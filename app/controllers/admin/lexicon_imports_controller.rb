# frozen_string_literal: true

# A language's imports on the admin page: the Import modal and its start,
# going on with one that waited for its cases to be confirmed, stopping one,
# and the assistant tests run again on the active one.
class Admin::LexiconImportsController < Admin::BaseController
  before_action :set_language
  before_action :set_import, only: %i[resume cancel evaluate]

  # Download the extract again, or use the file the last download kept.
  def new
    remote = begin
      Lexicon::Source.new(url: @language.to_config.url).head
    rescue Lexicon::Source::Error => e
      { error: e.message }
    end
    modal = Views::Admin::Lexicons::Modals::Import.new(language: @language.to_config, remote: remote, kept: Lexicon::Downloads.info(@language.code))
    render_modal(modal, page: @language)
  end

  # Without a kept file, the extract is downloaded whatever was picked.
  def create
    result = Lexicon::StartImport.call(@language, by: current_profile,
                                                  download: params[:download] != "0" || Lexicon::Downloads.info(@language.code).nil?)
    case result.error
    when nil then toast_flash(:notice, t("admin.lexicons.notices.started", language: @language.wiktionary))
    when :already_running then toast_flash(:alert, t("admin.lexicons.notices.already_running", language: @language.wiktionary))
    else toast_flash(:alert, result.import.error)
    end
    redirect_to admin_lexicon_path(@language.code), status: :see_other
  end

  # Only an import waiting for review goes on; one that has moved on since
  # the page was drawn is simply shown.
  def resume
    if !@import.awaiting_review?
      nil
    elsif @import.enqueue!(resume: true, fail_on_error: false, notify: current_profile.id)
      toast_flash(:notice, t("admin.lexicons.notices.continuing", language: @language.wiktionary))
    else
      toast_flash(:alert, @import.enqueue_failure)
    end
    redirect_to admin_lexicon_path(@language.code, import: @import.id), status: :see_other
  end

  def cancel
    outcome = @import.running? || @import.awaiting_review? ? @import.cancel! : :finished
    toast_flash(outcome == :finished ? :alert : :notice, t("admin.lexicons.notices.cancel_#{outcome}", language: @language.wiktionary))
    redirect_to admin_lexicon_path(@language.code, import: @import.id), status: :see_other
  end

  def evaluate
    if !@import.active?
      toast_flash(:alert, t("admin.lexicons.notices.nothing_active", language: @language.wiktionary))
    elsif Lexicon::AgentEval::Report.of(@import).running?
      toast_flash(:alert, t("admin.lexicons.notices.already_evaluating", language: @language.wiktionary))
    else
      Lexicon::AgentEvalJob.start(@import, by: current_profile)
      toast_flash(:notice, t("admin.lexicons.notices.evaluating", language: @language.wiktionary))
    end
    redirect_to admin_lexicon_path(@language.code), status: :see_other
  end

  private

  def set_language
    @language = LexiconLanguage.find_by!(code: params[:lexicon_language])
  end

  def set_import
    @import = LexiconImport.where(language: @language.code).find(params[:id])
  end
end
