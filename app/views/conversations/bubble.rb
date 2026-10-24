# frozen_string_literal: true

# One message as `viewer` sees it: theirs on the right, the others' on the
# left with who said it (in the household's conversation). Pictures, then
# the words (links made clickable, nothing else interpreted), the time,
# the reactions under it with the way to add one, and, on one's own, the
# way to unsend it. Replaced whole when unsent (its id is the
# message's); a reaction only updates its Reactions region.
#
# Pictures are linked by path, never by `image_tag` with a variant: this
# bubble is also rendered outside a request (the live push), where the
# renderer's host is example.org and a full URL would point there.
class Views::Conversations::Bubble < Views::Base
  def self.dom_id(message) = "message_#{message.id}"

  def initialize(message:, viewer:)
    @message = message
    @viewer = viewer
    @mine = message.sender_id == viewer.id
  end

  def view_template
    article(id: self.class.dom_id(@message), class: [ "message", @mine ? "message--mine" : "message--theirs", ("message--deleted" if @message.deleted?) ],
            data: { message_id: @message.id, mine: @mine.to_s }) do
      div(class: "message__main") do
        div(class: "message__bubble") do
          span(class: "message__sender") { @message.sender.display_name } if !@mine && @message.conversation.household?
          if @message.deleted?
            p(class: "message__text message__text--deleted") { t("conversations.message.deleted") }
          else
            pictures
            text
          end
          time_line
        end
        tools unless @message.deleted?
      end
      render Views::Conversations::Reactions.new(message: @message, viewer: @viewer)
    end
  end

  private

  # Each shown shrunk (Message#images' :shown variant), the picture as sent
  # on a tap — both through MessagePicturesController, which serves them to
  # the conversation's people alone and lets their browser keep them.
  def pictures
    images = @message.images.to_a
    return if images.empty?

    div(class: [ "message__pictures", ("message__pictures--several" if images.size > 1) ]) do
      images.each do |image|
        a(href: original_message_picture_path(@message, image), target: "_blank", rel: "noopener", class: "message__picture-link") do
          img(src: message_picture_path(@message, image), class: "message__picture", loading: "lazy",
              alt: t("conversations.message.picture_alt", name: @message.sender.display_name))
        end
      end
    end
  end

  def text
    body = @message.body.to_s
    return if body.blank?

    p(class: "message__text") do
      body.each_line.with_index do |line, index|
        br if index.positive?
        line.chomp.split(/(#{Message::URL})/o).each do |part|
          part.match?(/\A#{Message::URL}\z/o) ? a(href: part, target: "_blank", rel: "noopener noreferrer", class: "message__link") { part } : plain(part)
        end
      end
    end
  end

  def time_line
    at = @message.created_at.in_time_zone # the zone in scope: whoever this bubble is for
    time(class: "message__time", datetime: @message.created_at.iso8601, title: l(at, format: :long)) do
      at.today? ? l(at, format: t("time.formats.hour_minute")) : "#{l(at.to_date, format: :short)}, #{l(at, format: t("time.formats.hour_minute"))}"
    end
  end

  # React (the page's quick emoji, Views::Conversations::ReactionPicker)
  # and, on one's own, unsend.
  def tools
    div(class: "message__tools") do
      react_button
      if @mine
        render Components::ItemAction.new(href: message_path(@message), icon: "fa-trash", label: t("conversations.message.unsend"), turbo_stream: true,
                                          method: :delete, confirm: t("conversations.message.unsend_confirm"), danger: true)
      end
    end
  end

  def react_button
    picker = Views::Conversations::ReactionPicker
    label = t("conversations.reactions.add")
    button(type: "button", class: "item-action message__tool", title: label,
           aria: { label: label, expanded: "false", controls: picker::ID },
           data: picker.opener_data(url: message_reaction_path(@message), message_id: self.class.dom_id(@message), mine: @mine)) do
      render Components::Icon.new("fa-face-smile", style: :regular)
    end
  end
end
