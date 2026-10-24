# frozen_string_literal: true

class Views::Assistant::Chats::Modals::Form < Views::Base
  def initialize(chat:)
    @chat = chat
  end

  def view_template
    render Components::Modal.new(size: :small) do |modal|
      modal.modal_header(title: t("assistant.chats.form.title"), subtitle: t("assistant.chats.form.subtitle"), icon: "fa-pen")

      render Components::Form.new(record: @chat, url: assistant_chat_path(@chat), submit_text: t("assistant.chats.form.submit"), modal: modal) do |f|
        render Components::Field.new(label: t("assistant.chats.form.title_label"), control_id: "assistant_chat_title") do
          f.text_field :title,
                       class: "input is-medium",
                       placeholder: t("assistant.chats.form.title_placeholder"),
                       maxlength: ::Assistant::Chat::TITLE_MAX_LENGTH,
                       autofocus: true,
                       required: true
        end
      end
    end
  end
end
