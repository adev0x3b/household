# frozen_string_literal: true

# A new name for the household's conversation. Blank takes it back to the household's own name.
class Views::Conversations::Modals::Rename < Views::Base
  def initialize(conversation:)
    @conversation = conversation
  end

  def view_template
    render Components::Modal.new(size: :small, section: :messages) do |modal|
      modal.modal_header(title: t("conversations.rename.title"), subtitle: t("conversations.rename.subtitle"), icon: "fa-people-roof")

      render Components::Form.new(record: @conversation, url: conversation_path(@conversation), submit_text: t("conversations.rename.submit"), modal: modal) do |f|
        render Components::Field.new(label: t("conversations.rename.name_label"), control_id: f.field_id(:name),
                                     help: t("conversations.rename.help"), errors: Forms::Errors.new(@conversation).for(:name)) do |field|
          f.text_field :name, class: "input is-medium", maxlength: Conversation::NAME_LENGTH, autofocus: true,
                              placeholder: t("conversations.household.default_name", household: @conversation.household.name), aria: field.aria
        end
      end
    end
  end
end
