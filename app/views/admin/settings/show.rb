# frozen_string_literal: true

# /admin/settings: what the admin sets for the whole installation, one card
# per section, the same sections the first setup asks (Installation::*):
# what the installation allows, the bookshelf's sources, the mail it sends,
# the deploy token, the demo household's password. One form and one save. A secret is never
# shown back (Views::Installation::SecretField). The assistant's own
# settings have their page (/assistant/settings), linked at the top.
class Views::Admin::Settings::Show < Views::Base
  include Phlex::Rails::Helpers::FormWith

  # sections: the Installation sections by param key, as they are in use or
  # as a rejected save left them. token_expiry: the deploy token's
  # (Delivery::TokenExpiry). ask_password: the save waits for the admin's
  # password (Admin::Sudo); wrong_password: the last one typed wasn't theirs.
  def initialize(sections:, token_expiry:, ask_password: false, wrong_password: false)
    @sections = sections
    @token_expiry = token_expiry
    @ask_password = ask_password
    @wrong_password = wrong_password
  end

  def page_title = t("admin.settings.title")

  def view_template
    div(class: "report-page admin-settings") do
      render Components::PageHeader.new(title: t("admin.settings.title"))
      p(class: "report-hint") { t("admin.settings.hint") }
      assistant_notice
      @sections.each_value { |section| render Components::ErrorSummary.new(record: section) }
      form_with(url: admin_settings_path, method: :patch, scope: :settings, class: "report-form") do |f|
        section(f, :allowances) { |form, section| render Views::Installation::Allowances.new(form:, section:) }
        section(f, :books) { |form, section| render Views::Installation::Books.new(form:, section:) }
        section(f, :mail) { |form, section| render Views::Installation::Mail.new(form:, section:) }
        section(f, :deploy_token) { |form, section| render Views::Installation::DeployToken.new(form:, section:, token_expiry: @token_expiry) }
        section(f, :demo_password) { |form, section| render Views::Installation::DemoPassword.new(form:, section:) }
        render Views::Admin::SettingsPassword.new(form: f, wrong: @wrong_password) if @ask_password
        footer
      end
    end
  end

  private

  def section(f, key)
    f.fields_for(key, @sections.fetch(key)) { |form| yield form, @sections.fetch(key) }
  end

  def assistant_notice
    render Components::Notice.new(tone: :neutral) do
      p do
        plain t("admin.settings.assistant")
        whitespace
        a(href: assistant_settings_path) { t("admin.settings.assistant_link") }
      end
    end
  end

  def footer
    div(class: "report-footer") do
      button(type: "submit", class: "modal__btn modal__btn--primary") do
        render Components::Icon.new("fa-floppy-disk")
        whitespace
        plain t("admin.settings.save")
      end
    end
  end
end
