# frozen_string_literal: true

class Views::Devise::Invitations::Edit < Views::Base
  include Phlex::Rails::Helpers::FormFor
  include Phlex::Rails::Helpers::T

  def initialize(resource:, resource_name:)
    @resource = resource
    @resource_name = resource_name
  end

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        render_header
        render_form
      end
    end
  end

  private

  def render_header
    div(class: "auth-card__header") do
      h1(class: "auth-card__title") { t("invitations.edit.title", household: @resource.household.name) }
      p(class: "auth-card__subtitle") { t("invitations.edit.subtitle", household: @resource.household.name) }
    end
  end

  def render_form
    form_for(@resource, as: @resource_name, url: profile_invitation_path, html: { method: :put, "data-turbo": "false" }) do |f|
      render Components::ErrorSummary.new(record: @resource)
      render_hidden_field(f)
      render_text_field(f, :username, autocomplete: "username", required: true, autocapitalize: "none")
      render_text_field(f, :first_name, autocomplete: "given-name")
      render_password_fields(f) if @resource.class.require_password_on_accepting
      render_submit_button(f)
    end
  end

  def render_hidden_field(f)
    f.hidden_field :invitation_token, readonly: true
  end

  def render_text_field(f, attribute, **options)
    render Components::Field.new(label: t("invitations.edit.#{attribute}_label"), control_id: "#{@resource_name}_#{attribute}",
                                 errors: form_errors.for(attribute)) do |field|
      f.text_field attribute, class: "input is-medium", aria: field.aria, **options
    end
  end

  def render_password_fields(f)
    %i[password password_confirmation].each do |attribute|
      render Components::PasswordField.new(form: f, attribute:, label: t("invitations.edit.#{attribute}_label"), new_password: true,
                                           placeholder: t("invitations.edit.#{attribute}_placeholder"), errors: form_errors.for(attribute))
    end
  end

  def form_errors = @form_errors ||= Forms::Errors.new(@resource)

  def render_submit_button(f)
    div(class: "field") do
      div(class: "control") do
        f.submit t("invitations.edit.submit"), class: "button is-primary is-fullwidth is-medium"
      end
    end
  end
end
