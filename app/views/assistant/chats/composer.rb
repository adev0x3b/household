# frozen_string_literal: true

# The message input. While a reply runs it shows a stop button instead of
# send, because the chat takes one reply at a time. Photos (a lab report in
# several screenshots) go with or instead of typed text, where the
# installation allows them (Assistant::ChatPolicy#attach?).
class Views::Assistant::Chats::Composer < Views::Base
  ID = "assistant-composer"

  # messages_left: what the household may still send today, nil when there
  # is no limit (Assistant::MessageAllowance#left); attach: whether photos
  # may go with a message (Assistant::ChatPolicy#attach?).
  def initialize(chat:, messages_left:, attach:, busy: false)
    @chat = chat
    @messages_left = messages_left
    @attach = attach
    @busy = busy
  end

  def view_template
    form(id: ID, class: "assistant-composer", action: assistant_chat_messages_path(@chat), method: "post",
         enctype: "multipart/form-data",
         data: { assistant_chat_target: "form", action: "submit->assistant-chat#submit turbo:submit-end->assistant-chat#reset", turbo_stream: true }) do
      input(type: "hidden", name: "time_zone", data: { assistant_chat_target: "timeZone" })
      render_preview
      allowance unless @messages_left.nil?
      cloud_notice if ::Assistant.cloud?
      div(class: "assistant-composer__row") do
        attach_button if @attach && !@busy
        input(type: "file", name: "images[]", accept: "image/*", multiple: true, hidden: true,
              data: { assistant_chat_target: "fileInput", action: "change->assistant-chat#previewFile",
                      max_files: ::Assistant::Message::MAX_IMAGES })
        textarea(
          name: "content", rows: 1, maxlength: ::Assistant::Message::MAX_LENGTH,
          class: "assistant-composer__input", placeholder: t("assistant.composer.placeholder"), aria: { label: t("assistant.composer.placeholder") },
          disabled: @busy, data: { assistant_chat_target: "input", action: "keydown->assistant-chat#keydown input->assistant-chat#grow" }
        )
        if @busy
          a(href: assistant_chat_reply_path(@chat), class: "assistant-composer__btn assistant-composer__btn--stop",
            aria: { label: t("assistant.composer.stop") }, data: { turbo_method: :delete, turbo_stream: true }) do
            render Components::Icon.new("fa-stop")
          end
        else
          button(type: "submit", class: "assistant-composer__btn", aria: { label: t("assistant.composer.send") }) do
            render Components::Icon.new("fa-paper-plane")
          end
        end
      end
    end
  end

  private

  # The whole household shares one daily allowance, so the count is the household's.
  def allowance
    p(class: "assistant-composer__allowance") do
      t("assistant.composer.left_today", count: @messages_left, max: ::Platform.assistant_messages_per_day)
    end
  end

  # With a cloud provider, what is typed here (health data included) leaves
  # the household's server, so the user is told.
  def cloud_notice
    p(class: "assistant-composer__allowance assistant-composer__allowance--cloud") do
      render Components::Icon.new("fa-cloud-arrow-up")
      plain " #{t("assistant.composer.cloud_notice", provider: t("assistant.settings.providers.#{::Assistant.provider}.name"))}"
    end
  end

  def attach_button
    button(type: "button", class: "assistant-composer__btn assistant-composer__btn--attach", aria: { label: t("assistant.composer.attach_image") },
           data: { action: "click->assistant-chat#pickFile" }) { render Components::Icon.new("fa-paperclip") }
  end

  # The thumbnails are drawn from the template, one per photo, by
  # assistant_chat_controller.js; the photo itself is the only thing it fills in.
  def render_preview
    div(class: "assistant-composer__preview", hidden: true, data: { assistant_chat_target: "preview" }) do
      div(class: "assistant-composer__preview-images", data: { assistant_chat_target: "previewImages" })
      template(data: { assistant_chat_target: "previewTemplate" }) { img(class: "assistant-composer__preview-image", alt: "") }
      button(type: "button", class: "assistant-composer__preview-remove", aria: { label: t("assistant.composer.remove_image") },
             data: { action: "click->assistant-chat#clearFile" }) { render Components::Icon.new("fa-xmark") }
    end
  end
end
