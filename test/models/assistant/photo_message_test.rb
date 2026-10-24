# frozen_string_literal: true

require "test_helper"

# Assistant::PhotoMessage: a user's message about photos, read back into the
# caption they typed and the text the app read from the photos.
class Assistant::PhotoMessageTest < ActiveSupport::TestCase
  test "a message the OCR job wrote splits into its caption and the photos' text" do
    content = Assistant::LabReportOcrJob.attach_text("My results", [ "Glucosio 92 mg/dL", nil ])
    message = Assistant::PhotoMessage.new(content)

    assert_equal "My results", message.caption
    assert_equal "Page 1 of 2:\nGlucosio 92 mg/dL\n\nPage 2 of 2:\n#{Assistant::PhotoMessage::UNREADABLE_PAGE}", message.photo_text
  end

  test "a typed message is its own caption, with no photo text" do
    message = Assistant::PhotoMessage.new("I took my B12 today")

    assert_equal "I took my B12 today", message.caption
    assert_nil message.photo_text
  end
end
