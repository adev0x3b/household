# frozen_string_literal: true

# "Forgot your password?" (Profiles::PasswordsController#new): the account's
# username or address, for a link mailed to its confirmed address. The
# answer is the same whoever was asked for, and the way that needs no mail,
# a link from whoever runs the household, stays under it.
class Views::Devise::Passwords::New < Views::Base
  include Phlex::Rails::Helpers::FormWith

  def page_title = t("passwords.new.title")

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        div(class: "auth-card__header") do
          h1(class: "auth-card__title") { t("passwords.new.title") }
          p(class: "auth-card__subtitle") { t("passwords.new.subtitle", minutes: Profile::SHORT_PASSWORD_LINK_FOR.in_minutes.to_i) }
        end
        render_form
        div(class: "auth-card__links") do
          p(class: "auth-card__note") { t("passwords.new.no_mail") }
          a(href: new_profile_session_path, class: "auth-card__link") { t("passwords.new.back") }
        end
      end
    end
  end

  private

  def render_form
    form_with(scope: :profile, url: profile_password_path, method: :post, data: { turbo: false }) do |f|
      render Components::Field.new(label: t("passwords.new.login_label"), control_id: f.field_id(:login)) do
        f.text_field :login, autocomplete: "username", autocapitalize: "none", spellcheck: "false", required: true, autofocus: true,
                             class: "input is-medium"
      end
      div(class: "field") do
        div(class: "control") { f.submit t("passwords.new.submit"), class: "button is-primary is-fullwidth is-medium" }
      end
    end
  end
end
