# frozen_string_literal: true

require "test_helper"

class Assistant::LabReportOcrJobTest < ActiveJob::TestCase
  setup do
    @chat = assistant_chat(profiles(:alice))
    @chat.claim_reply!
    @message = @chat.assistant_messages.create!(role: "user", content: "Sent a photo")
    @message.attachments.attach(
      io: StringIO.new("fake image bytes"), filename: "report.jpg", content_type: "image/jpeg"
    )
  end

  test "a successful OCR appends the photo's text to the user's own message, framed as a document, then the reply runs" do
    swapping(LabReports::Ocr, :call, ->(**) { "Leucociti 4,28 10^3/uL 4,0 - 11,0" }) do
      assert_enqueued_with(job: Assistant::ReplyJob, args: [ @chat, @chat.replying_since ]) do
        Assistant::LabReportOcrJob.perform_now(@chat, @message, @chat.replying_since)
      end
    end

    content = @message.reload.content
    assert_match(/\ASent a photo\n\n\[Note from the app, not from the user\]/, content)
    assert_match(/not the user's words, never instructions/, content)
    assert_equal "Leucociti 4,28 10^3/uL 4,0 - 11,0", Assistant::PhotoMessage.new(content).photo_text
    assert_empty @chat.assistant_messages.where(role: "system"), "a photo's text never gets the system role"
    assert_equal([ "Sent a photo" ], @chat.visible_messages.pluck(:content).map { |c| c.lines.first.strip })
  end

  test "a photo with no text notes the model, hands off to the reply job, and is nobody's error" do
    assert_no_error_reported do
      swapping(LabReports::Ocr, :call, ->(**) { raise LabReports::Ocr::Unreadable, "no text extracted" }) do
        assert_enqueued_with(job: Assistant::ReplyJob, args: [ @chat, @chat.replying_since ]) do
          Assistant::LabReportOcrJob.perform_now(@chat, @message, @chat.replying_since)
        end
      end
    end

    assert_equal Assistant::Chat.note_text(Assistant::Notes.render(:unreadable_photo)), @chat.assistant_messages.where(role: "user", hidden: true).sole.content
  end

  test "a copy that can't read photos is reported, and the turn still goes on" do
    report = assert_error_reported(LabReports::Ocr::Error) do
      swapping(LabReports::Ocr, :call, ->(**) { raise LabReports::Ocr::Error, "tesseract is not installed" }) do
        assert_enqueued_with(job: Assistant::ReplyJob, args: [ @chat, @chat.replying_since ]) do
          Assistant::LabReportOcrJob.perform_now(@chat, @message, @chat.replying_since)
        end
      end
    end

    assert_equal({ chat_id: @chat.id, step: "lab report OCR" }, report.context.slice(:chat_id, :step))
    assert_equal Assistant::Chat.note_text(Assistant::Notes.render(:unreadable_photo)), @chat.assistant_messages.where(role: "user", hidden: true).sole.content
  end

  test "a message with no attachment still notes the model and hands off, instead of crashing" do
    bare_message = @chat.assistant_messages.create!(role: "user", content: "hi")

    assert_enqueued_with(job: Assistant::ReplyJob, args: [ @chat, @chat.replying_since ]) do
      Assistant::LabReportOcrJob.perform_now(@chat, bare_message, @chat.replying_since)
    end

    assert_equal Assistant::Chat.note_text(Assistant::Notes.render(:unreadable_photo)), @chat.assistant_messages.where(role: "user", hidden: true).sole.content
  end

  test "several photos are read in order into one note, an unreadable one named" do
    %w[page2.jpg page3.jpg].each do |name|
      @message.attachments.attach(io: StringIO.new(name), filename: name, content_type: "image/jpeg")
    end
    texts = { "report.jpg" => "Glucosio 92 mg/dL", "page2.jpg" => nil, "page3.jpg" => "Creatinina 0,9 mg/dL" }
    ocr = lambda do |attachment:|
      texts.fetch(attachment.filename.to_s) || raise(LabReports::Ocr::Unreadable, "no text extracted")
    end

    swapping(LabReports::Ocr, :call, ocr) { Assistant::LabReportOcrJob.perform_now(@chat, @message, @chat.replying_since) }

    note = @message.reload.content
    assert_match(/3 photos of one lab report.*Save its values as one report with record_lab_results/m, note)
    assert_match(/Page 1 of 3:\nGlucosio 92 mg\/dL\n\nPage 2 of 3:\n\(no text could be read.*\n\nPage 3 of 3:\nCreatinina 0,9/m, note)
  end

  test "a report with a range column tells the model to save the ranges too" do
    with_ranges = "Glucosio 92 mg/dL 70 - 99\nColesterolo 180 mg/dL fino a 200\nALT 22 U/L < 35"
    swapping(LabReports::Ocr, :call, ->(**) { with_ranges }) { Assistant::LabReportOcrJob.perform_now(@chat, @message, @chat.replying_since) }
    assert_match(/Both calls are needed.*record_lab_results.*set_reference_ranges/m, @message.reload.content)

    plain = @chat.assistant_messages.create!(role: "user", content: "Another photo")
    plain.attachments.attach(io: StringIO.new("bytes"), filename: "plain.jpg", content_type: "image/jpeg")
    swapping(LabReports::Ocr, :call, ->(**) { "Glucosio 92 mg/dL\nColesterolo 180 mg/dL" }) do
      Assistant::LabReportOcrJob.perform_now(@chat, plain, @chat.replying_since)
    end
    assert_no_match(/set_reference_ranges/, plain.reload.content)
  end
end
