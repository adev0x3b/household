# frozen_string_literal: true

# The sign-in page. Where the installation has open accounts (the demo's:
# Platform.open_accounts), it is the demo's door first: what the demo is,
# and each account as a button, with the form for whoever has an account
# of their own below. A button is a POST to DemosController#create, a full
# page load like signing in, never a link a GET could follow. Elsewhere, when there is a
# demo installation to try (DEMO_HOST), a link to it.
class Views::Devise::Sessions::New < Views::Base
  include Phlex::Rails::Helpers::FormFor
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::T

  # open_profiles: the accounts anyone may enter as (Platform.open_profiles);
  # demo_url: another copy's demo to try (none on the demo itself).
  def initialize(resource:, resource_name:, devise_mapping:, open_profiles: [], demo_url: nil)
    @open_profiles = open_profiles
    @demo_url = demo_url
    @resource = resource
    @resource_name = resource_name
    @devise_mapping = devise_mapping
  end

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        if @open_profiles.any?
          render_demo_header
          render_open_accounts
        else
          render_header
        end
        render_form
        render_links
      end
    end
  end

  private

  def render_header
    div(class: "auth-card__header") do
      h1(class: "auth-card__title") { t("sessions.new.title") }
      p(class: "auth-card__subtitle") { t("sessions.new.subtitle") }
    end
  end

  def render_demo_header
    div(class: "auth-card__header") do
      h1(class: "auth-card__title") { t("demo.sign_in.title") }
      p(class: "auth-card__subtitle") { t("demo.welcome") }
    end
  end

  # Each open account is a button; then the form, for whoever has an account.
  def render_open_accounts
    p(class: "auth-card__note") { t("demo.sign_in.pick") }
    div(class: "demo-personas") do
      @open_profiles.each do |person|
        button_to t("demo.sign_in.enter_as", name: person.display_name), demo_path, params: { as: person.username },
                                                                                    form: { data: { turbo: false } }, form_class: "demo-personas__form", class: "button is-primary is-fullwidth is-medium"
      end
    end
    p(class: "auth-card__note") { t("demo.sign_in.account") }
  end

  def render_form
    form_for(@resource, as: @resource_name, url: profile_session_path, html: { "data-turbo": "false" }) do |f|
      render_login_field(f)
      render_password_field(f)
      render_remember_me(f) if @devise_mapping.rememberable?
      render_submit_button(f)
    end
  end

  def render_login_field(f)
    render Components::Field.new(label: t("sessions.new.login_placeholder"), control_id: f.field_id(:login), label_hidden: true) do
      f.text_field :login,
                   placeholder: t("sessions.new.login_placeholder"),
                   autofocus: @open_profiles.empty?,
                   autocomplete: "username",
                   autocapitalize: "none",
                   required: true,
                   class: "input is-medium"
    end
  end

  def render_password_field(f)
    render Components::PasswordField.new(form: f, attribute: :password, label: t("sessions.new.password_placeholder"), label_hidden: true,
                                         placeholder: t("sessions.new.password_placeholder"))
  end

  def render_remember_me(f)
    div(class: "field") do
      div(class: "control") do
        label(class: "checkbox") do
          # Ticked: on one's own phone one stays signed in; untick on a shared one.
          f.check_box :remember_me, checked: true
          whitespace
          plain t("sessions.new.remember_me")
        end
      end
    end
  end

  def render_submit_button(f)
    div(class: "field") do
      div(class: "control") do
        f.submit t("sessions.new.submit"), class: "button is-primary is-fullwidth is-medium"
      end
    end
  end

  # No email resets a password here: whoever runs the household makes a link.
  def render_links
    div(class: "auth-card__links") do
      p(class: "auth-card__note") { t("sessions.new.forgot") }
      a(href: @demo_url, class: "auth-card__link") { t("demo.sign_in_link") } if @demo_url
    end
  end
end
