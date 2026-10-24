# frozen_string_literal: true

# Where a message is written: words, pictures (up to Message::MAX_IMAGES,
# previewed before they go; none where the installation has them off,
# MessagePolicy#attach?), and the send button. Pictures come from the camera (a file input with `capture`, which
# a phone answers by opening its camera) or the library; both feed one
# list the form submits, so several shots can be taken one after the other
# (conversation_controller.js). Enter sends on a keyboard, adds a line on
# a phone. The hidden client id is minted by the page and renewed after
# every send: a send repeated by a bad connection saves one message
# (Messages::Send).
class Views::Conversations::Composer < Views::Base
  def initialize(conversation:, viewer:)
    @conversation = conversation
    @viewer = viewer
  end

  def view_template
    form(class: "conversation-composer", action: conversation_messages_path(@conversation), method: "post", enctype: "multipart/form-data",
         data: { conversation_target: "form", action: "submit->conversation#submit turbo:submit-end->conversation#sent", turbo_stream: true }) do
      input(type: "hidden", name: "client_id", data: { conversation_target: "clientId" })
      preview
      div(class: "conversation-composer__row") do
        pictures if Pundit.policy!(@viewer, Message.new(conversation: @conversation)).attach?
        textarea(name: "body", rows: 1, maxlength: Message::BODY_LENGTH, class: "conversation-composer__input",
                 placeholder: t("conversations.composer.placeholder"), aria: { label: t("conversations.composer.placeholder") },
                 data: { conversation_target: "body", action: "keydown->conversation#keydown input->conversation#grow" })
        button(type: "submit", class: "conversation-composer__send", aria: { label: t("conversations.composer.send") }) do
          render Components::Icon.new("fa-paper-plane")
        end
      end
    end
  end

  private

  # The camera and the library, each a button over its own nameless input;
  # what they pick lands in the one input the form sends.
  def pictures
    input(type: "file", name: "images[]", multiple: true, hidden: true, data: { conversation_target: "files", max_files: Message::MAX_IMAGES })
    input(type: "file", accept: "image/*", capture: "environment", hidden: true,
          data: { conversation_target: "camera", action: "change->conversation#addPictures" })
    input(type: "file", accept: Message::IMAGE_TYPES.join(","), multiple: true, hidden: true,
          data: { conversation_target: "library", action: "change->conversation#addPictures" })
    picture_button("fa-camera", t("conversations.composer.take_photo"), "click->conversation#openCamera")
    picture_button("fa-image", t("conversations.composer.attach"), "click->conversation#openLibrary")
  end

  def picture_button(icon, label, action)
    button(type: "button", class: "conversation-composer__attach", aria: { label: label }, title: label, data: { action: action }) do
      render Components::Icon.new(icon)
    end
  end

  # The thumbnails are drawn from the template, one per picture, by
  # conversation_controller.js; the picture itself is the only thing it fills in.
  def preview
    div(class: "conversation-composer__preview", hidden: true, data: { conversation_target: "preview" }) do
      div(class: "conversation-composer__preview-images", data: { conversation_target: "previewImages" })
      template(data: { conversation_target: "previewTemplate" }) do
        div(class: "conversation-composer__preview-item") do
          img(class: "conversation-composer__preview-image", alt: "")
          button(type: "button", class: "conversation-composer__preview-remove", aria: { label: t("conversations.composer.remove_picture") },
                 title: t("conversations.composer.remove_picture"), data: { action: "click->conversation#removePicture" }) do
            render Components::Icon.new("fa-xmark")
          end
        end
      end
    end
  end
end
