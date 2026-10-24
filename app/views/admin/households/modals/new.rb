# frozen_string_literal: true

# A new household: its name and who to invite first. That person invites
# the others.
class Views::Admin::Households::Modals::New < Views::Base
  INPUT = { class: "input is-medium", autocomplete: "off" }.freeze

  def initialize(household:)
    @household = household
  end

  def view_template
    render Components::Modal.new(size: :small) do |modal|
      modal.modal_header(title: t("admin.households.new.title"), icon: "fa-house-chimney")
      render Components::Form.new(record: @household, url: admin_households_path, method: :post,
                                  submit_text: t("admin.households.new.submit"), modal: modal) do |f|
        form_field(f, :name, label: t("admin.households.new.name_label"), required: true) do |field|
          f.text_field(:name, required: true, autofocus: true, **INPUT, aria: field.aria)
        end
        form_field(f, :first_member_email, label: t("admin.households.new.first_member_email_label"), required: true) do |field|
          f.email_field(:first_member_email, required: true, **INPUT, aria: field.aria)
        end
        form_field(f, :first_member_first_name, label: t("admin.households.new.first_member_first_name_label"), required: false) do |field|
          f.text_field(:first_member_first_name, **INPUT, aria: field.aria)
        end
        p(class: "help") { t("admin.households.new.what_happens") }
      end
    end
  end
end
