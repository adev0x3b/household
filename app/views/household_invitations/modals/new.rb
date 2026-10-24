# frozen_string_literal: true

# Inviting someone into a household: their email, and their first name if
# you like (they choose their own username and password when they accept).
class Views::HouseholdInvitations::Modals::New < Views::Base
  def initialize(profile:)
    @profile = profile
  end

  def view_template
    render Components::Modal.new(size: :small) do |modal|
      modal.modal_header(title: t("households.invite.title"), icon: "fa-user-plus")
      render Components::Form.new(record: @profile, url: household_invitations_path(@profile.household), method: :post,
                                  submit_text: t("households.invite.submit"), modal: modal) do |f|
        render Components::Field.new(label: t("households.invite.email_label"), control_id: "profile_email",
                                     errors: form_errors.for(:email)) do |field|
          f.email_field :email, class: "input is-medium", required: true, autofocus: true, autocomplete: "off",
                                placeholder: t("households.invite.email_placeholder"), aria: field.aria
        end
        render Components::Field.new(label: t("households.invite.first_name_label"), control_id: "profile_first_name",
                                     errors: form_errors.for(:first_name)) do |field|
          f.text_field :first_name, class: "input is-medium", autocomplete: "off", aria: field.aria
        end
        p(class: "help") { t("households.invite.what_happens", household: @profile.household.name) }
      end
    end
  end

  private

  def form_errors = @form_errors ||= Forms::Errors.new(@profile)
end
