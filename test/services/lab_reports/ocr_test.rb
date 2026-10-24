# frozen_string_literal: true

require "test_helper"

# Runs the real Tesseract binary and libvips against a synthetic fixture
# image (test/fixtures/files/lab_report_sample.png) — skipped when either
# isn't installed on this machine (both are always present in the
# production Docker image, see Dockerfile and app/services/lab_reports/ocr.rb).
class LabReports::OcrTest < ActiveSupport::TestCase
  setup do
    skip "tesseract is not installed" unless system("which", "tesseract", out: File::NULL, err: File::NULL)
    skip "libvips is not installed" unless vips_available?

    chat = assistant_chat(profiles(:alice))
    message = chat.assistant_messages.create!(role: "user", content: "Sent a photo")
    message.attachments.attach(
      io: File.open(file_fixture("lab_report_sample.png")), filename: "lab_report_sample.png", content_type: "image/png"
    )
    @attachment = message.attachments.first
  end

  test "extracts every row's analyte, value, unit and reference range" do
    text = LabReports::Ocr.call(attachment: @attachment)

    assert_match(/Glucose/i, text)
    assert_match "90", text
    assert_match "mg/dL", text
    assert_match(/70\s*-\s*100/, text)

    assert_match(/Cholesterol/i, text)
    assert_match "180", text
    assert_match "fino a 200", text

    assert_match(/Calcium/i, text)
    # The whole number, not a substring: a real screenshot once read "9.55".
    assert_match(/Calcium\s+9\.5\s+mg\/dL/, text)
    assert_match(/8.5\s*-\s*10.5/, text)
  end

  test "raises when the image has no readable text" do
    blank = Vips::Image.black(200, 100) + 255
    Tempfile.create([ "blank", ".png" ]) do |file|
      blank.cast(:uchar).write_to_file(file.path)
      chat = assistant_chat(profiles(:alice))
      message = chat.assistant_messages.create!(role: "user", content: "Sent a photo")
      message.attachments.attach(io: File.open(file.path), filename: "blank.png", content_type: "image/png")

      assert_raises(LabReports::Ocr::Unreadable) { LabReports::Ocr.call(attachment: message.attachments.first) }
    end
  end

  test "a dark-mode screenshot, with its alpha band, reads like the light one" do
    dark = Vips::Image.new_from_file(file_fixture("lab_report_sample.png").to_s).colourspace("b-w").extract_band(0).invert
    Tempfile.create([ "dark", ".png" ]) do |file|
      dark.bandjoin(255).write_to_file(file.path) # a grey band and an alpha band
      assert_match(/Glucose\s+90\s+mg\/dL/i, LabReports::Ocr.call(attachment: attached(file.path)))
    end
  end

  test "Tesseract failing is the copy's error; reading nothing is the photo's" do
    failed = Struct.new(:success?).new(false)
    swapping(Open3, :capture3, ->(*) { [ "", "image too small", failed ] }) do
      error = assert_raises(LabReports::Ocr::Error) { LabReports::Ocr.call(attachment: @attachment) }
      assert_match "tesseract failed: image too small", error.message
      assert_not_kind_of LabReports::Ocr::Unreadable, error
    end
    swapping(Open3, :capture3, ->(*) { [ "\n  \n", "", Struct.new(:success?).new(true) ] }) do
      assert_match "no text extracted", assert_raises(LabReports::Ocr::Unreadable) { LabReports::Ocr.call(attachment: @attachment) }.message
    end
  end

  private

  def attached(path)
    message = assistant_chat(profiles(:alice)).assistant_messages.create!(role: "user", content: "Sent a photo")
    message.attachments.attach(io: File.open(path), filename: File.basename(path), content_type: "image/png")
    message.attachments.first
  end

  def vips_available?
    require "vips"
    true
  rescue LoadError
    false
  end
end
