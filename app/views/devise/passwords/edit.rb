# frozen_string_literal: true

# Choosing a new password from a reset link (Profiles::PasswordsController).
class Views::Devise::Passwords::Edit < Views::Base
  include Phlex::Rails::Helpers::FormFor

  def initialize(resource:, resource_name:)
    @resource = resource
    @resource_name = resource_name
  end

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        div(class: "auth-card__header") do
          h1(class: "auth-card__title") { t("passwords.edit.title") }
          p(class: "auth-card__subtitle") { t("passwords.edit.subtitle") }
        end
        render_form
      end
    end
  end

  private

  def render_form
    form_for(@resource, as: @resource_name, url: profile_password_path, html: { method: :put, "data-turbo": "false" }) do |f|
      render Components::ErrorSummary.new(record: @resource)
      f.hidden_field :reset_password_token
      password_field(f, :password, autofocus: true)
      password_field(f, :password_confirmation)
      div(class: "field") do
        div(class: "control") { f.submit t("passwords.edit.submit"), class: "button is-primary is-fullwidth is-medium" }
      end
    end
  end

  def password_field(f, attribute, **options)
    render Components::PasswordField.new(form: f, attribute:, label: t("passwords.edit.#{attribute}_label"), new_password: true,
                                         errors: Forms::Errors.new(@resource).for(attribute), **options)
  end
end
