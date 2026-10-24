# frozen_string_literal: true

# Importing a language again: download its extract afresh from kaikki.org
# (what's there now: size and date), or use the file the last download kept
# (Lexicon::Downloads) — then every step runs again, the dictionary check
# and the assistant test included; the active import stays in use until the
# new one passes.
class Views::Admin::Lexicons::Modals::Import < Views::Base
  # remote: Lexicon::Source#head, or { error: } when kaikki.org can't be reached;
  # kept: Lexicon::Downloads.info, or nil.
  def initialize(language:, remote:, kept:)
    @language = language
    @remote = remote
    @kept = kept
  end

  def view_template
    render Components::Modal.new(size: :medium) do |modal|
      modal.modal_header(title: t("admin.lexicons.import", language: @language.wiktionary), icon: "fa-cloud-arrow-down")
      modal.modal_form(url: admin_lexicon_imports_path(@language.code), method: :post, data: { turbo: true }) do |f|
        modal.modal_body do
          fieldset(class: "report-choices") do
            legend(class: "label") { t("admin.lexicons.reimport.which_file") }
            choice(f, "1", t("admin.lexicons.reimport.download"), remote_detail, checked: @kept.nil?, disabled: @remote[:error].present? && @kept)
            choice(f, "0", t("admin.lexicons.reimport.kept"), kept_detail, checked: @kept.present?, disabled: @kept.nil?)
          end
          p(class: "help") { t("admin.lexicons.reimport.what_runs") }
        end
        modal.modal_footer do
          div(class: "modal__footer-main") do
            f.submit t("admin.lexicons.reimport.submit"), class: "modal__btn modal__btn--primary"
          end
        end
      end
    end
  end

  private

  def choice(f, value, title, detail, checked:, disabled:)
    label(class: "report-choice#{" is-disabled" if disabled}") do
      f.radio_button :download, value, checked: checked && !disabled, disabled: disabled
      span(class: "report-choice__text") do
        strong { title }
        span(class: "help") { detail }
      end
    end
  end

  def remote_detail
    return t("admin.lexicons.reimport.unreachable", error: @remote[:error]) if @remote[:error]

    t("admin.lexicons.reimport.remote", size: size(@remote[:size]), date: @remote[:last_modified] ? l(@remote[:last_modified].to_date, format: :long) : "?")
  end

  def kept_detail
    return t("admin.lexicons.reimport.none_kept") unless @kept

    t("admin.lexicons.reimport.kept_detail", size: size(@kept[:size]), date: l(@kept[:saved_at], format: :short))
  end

  def size(bytes) = bytes ? ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: I18n.locale) : "?"
end
