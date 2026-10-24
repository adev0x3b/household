# frozen_string_literal: true

# Takes the user's message and hands the reply to a job, so the request never
# waits for the model. A chat runs one reply at a time.
class Assistant::MessagesController < ApplicationController
  include AssistantEnabled

  # A person types a few messages a minute; a script doesn't get further.
  rate_limit_per_person to: 20, within: 1.minute, only: :create, with: -> { refuse_in_thread(t("rate_limit.exceeded"), status: :too_many_requests) }

  def create
    chat = policy_scope(Assistant::Chat).find(params[:chat_id])
    authorize chat, :update?

    images = [ *params[:images], params[:image] ].compact_blank
    content = params[:content].to_s.strip
    return refuse_in_thread(t("assistant.errors.empty"), chat) if content.blank? && images.empty?
    return refuse_in_thread(t("assistant.errors.too_long", max: Assistant::Message::MAX_LENGTH), chat) if content.length > Assistant::Message::MAX_LENGTH
    if images.size > Assistant::Message::MAX_IMAGES || !images.all? { |image| valid_image?(image) }
      return refuse_in_thread(t("assistant.errors.unsupported_photos", max: Assistant::Message::MAX_IMAGES,
                                                                       size: helpers.number_to_human_size(Assistant::Message::MAX_ATTACHMENT_SIZE)), chat)
    end
    return refuse_in_thread(t("assistant.errors.images_off"), chat) if images.any? && !policy(chat).attach?
    return refuse_in_thread(t("assistant.errors.daily_limit", max: Platform.assistant_messages_per_day), chat) if !Assistant::MessageAllowance.new(current_profile.household).any_left?
    return refuse_in_thread(t("assistant.errors.busy"), chat) unless chat.claim_reply!

    chat.update!(time_zone: params[:time_zone]) if ActiveSupport::TimeZone[params[:time_zone].to_s] && chat.time_zone != params[:time_zone]
    chat.update!(locale: I18n.locale.to_s) if chat.locale != I18n.locale.to_s # replies follow the language the user picked
    content = t("assistant.defaults.lab_photo_caption") if content.blank?
    chat.update!(title: content.truncate(60)) if chat.title.blank?

    # The photos are attached here, not passed to ask_later: RubyLLM would
    # send them to the model, and a text-only model refuses them (see
    # Assistant::Message).
    message = chat.ask_later(content).assistant_messages.where(role: "user").order(:id).last
    message.attachments.attach(images) if images.any?

    if images.any?
      Assistant::LabReportOcrJob.perform_later(chat, message, chat.replying_since)
    else
      Assistant::ReplyJob.perform_later(chat, chat.replying_since)
    end
    Assistant::ReplyTimeoutJob.set(wait: Assistant::Chat::REPLY_TIMEOUT).perform_later(chat, chat.replying_since)

    render turbo_stream: [
      turbo_stream.remove(Views::Assistant::Chats::Show::WELCOME_ID),
      turbo_stream.append(Views::Assistant::Chats::Show::THREAD_ID,
                          Views::Assistant::Chats::MessageBubble.new(role: "user", content: message.content, attachments: message.attachments)),
      turbo_stream.append(Views::Assistant::Chats::Show::THREAD_ID, Views::Assistant::Chats::Reply.new(text: nil)),
      turbo_stream.replace(Views::Assistant::Chats::Composer::ID, composer(chat, busy: true))
    ], status: :accepted
  rescue StandardError
    chat&.release_reply!
    raise
  end

  private

  # Refused as everywhere else (ApplicationController#refuse), but the reason
  # goes into the thread, where the user is looking, and the composer is
  # given back.
  def refuse_in_thread(reason, chat = nil, status: :unprocessable_content)
    streams = [ turbo_stream.append(Views::Assistant::Chats::Show::THREAD_ID, Views::Assistant::Chats::Notice.new(kind: :error, text: reason)) ]
    streams << turbo_stream.replace(Views::Assistant::Chats::Composer::ID, composer(chat, busy: chat.replying?)) if chat
    render turbo_stream: streams, status: status
  end

  def composer(chat, busy:)
    Views::Assistant::Chats::Composer.new(chat: chat, busy: busy, messages_left: Assistant::MessageAllowance.new(current_profile.household).left,
                                          attach: policy(chat).attach?)
  end

  def valid_image?(file)
    file.respond_to?(:content_type) && file.content_type.in?(Assistant::Message::SUPPORTED_ATTACHMENT_TYPES) &&
      file.size.to_i <= Assistant::Message::MAX_ATTACHMENT_SIZE
  end
end
