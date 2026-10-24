# frozen_string_literal: true

# Reads a message's photos (several pages of one report, in order) and
# appends their text to the user's own message, between markers that say it
# is a document: data to save, never instructions. It is never a system
# message, because providers lift those into the system prompt and a photo
# must not speak with the app's authority. The model then reads it like
# typed lab values.
#
# It always hands off to ReplyJob in `ensure`, whatever happened, because
# the reply lock the message claimed is released by ReplyJob alone.
class Assistant::LabReportOcrJob < ApplicationJob
  queue_as :assistant
  runs_once

  # claimed_at: when the message claimed the chat, handed on to the reply.
  def perform(chat, message, claimed_at)
    attachments = message.attachments.order(:id).to_a

    if attachments.empty?
      Rails.logger.warn("[assistant] chat=#{chat.id} ocr: message=#{message.id} has no attachment")
      chat.note_for_model!(Assistant::Notes.render(:unreadable_photo))
      return
    end

    pages = attachments.map { |attachment| read(chat.id, attachment) }
    if pages.none?
      chat.note_for_model!(Assistant::Notes.render(:unreadable_photo))
    else
      message.update!(content: self.class.attach_text(message.content, pages))
    end
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { chat_id: chat.id, step: "lab report OCR" })
    chat.note_for_model!(Assistant::Notes.render(:unreadable_photo))
  ensure
    Assistant::ReplyJob.perform_later(chat, claimed_at)
  end

  # The user's message with the photos' text appended, as the model reads it
  # (Assistant::PhotoMessage). Also how an eval scenario's "!photo" turn
  # reaches the model.
  def self.attach_text(caption, pages) = "#{caption}\n\n#{Assistant::Chat.note_text(note(pages))}"

  # What the model is told for the photos' texts, in order (nil for a page
  # nothing could be read from).
  def self.note(pages)
    return Assistant::Notes.render(:unreadable_photo) if pages.none?

    intro = pages.size == 1 ? Assistant::Notes.render(:lab_report_photo) : Assistant::Notes.render(:lab_report_photos, count: pages.size)
    text = "#{intro}\n#{Assistant::PhotoMessage.framed(pages)}"
    # The ranges come after the text, so their note names the first call
    # again: without that, the model tends to take the last sentence as the
    # only thing to do and skips record_lab_results.
    ranges?(pages.compact.join("\n")) ? "#{text}\n\n#{Assistant::Notes.render(:lab_report_ranges)}" : text
  end

  # When most lines with a number also carry a range, the report has a
  # range column worth saving too.
  def self.ranges?(text)
    rows = text.lines.grep(/\d/)
    rows.any? && rows.count { |line| Assistant::RangeText.printed?(line) } * 2 >= rows.size
  end

  private

  # The page's text, or nil when nothing could be read from it. A photo
  # with no text is the person's to retake; a copy that can't read photos
  # at all is reported, for whoever runs it to fix.
  def read(chat_id, attachment)
    text = LabReports::Ocr.call(attachment: attachment)
    Rails.logger.info("[assistant] chat=#{chat_id} ocr extracted #{text.lines.count} lines")
    text
  rescue LabReports::Ocr::Unreadable
    nil
  rescue LabReports::Ocr::Error => e
    Rails.error.report(e, handled: true, context: { chat_id: chat_id, step: "lab report OCR" })
    nil
  end
end
