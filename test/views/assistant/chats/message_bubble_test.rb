# frozen_string_literal: true

require "test_helper"

class Views::Assistant::Chats::MessageBubbleTest < ActiveSupport::TestCase
  test "an assistant's bubble shows its answer and none of its thinking" do
    bubble = parse(role: "assistant", content: "<think>They mean the dentist.</think>Booked for **Tuesday**.")

    assert_equal "Booked for Tuesday.", bubble.at_css(".assistant-message__paragraph").text
    assert_equal "Tuesday", bubble.at_css("strong").text
    assert_no_match(/dentist/, bubble.text)
  end

  test "a photo's message shows the caption, with the text read from the photo folded away" do
    content = Assistant::LabReportOcrJob.attach_text("My results", [ "Glucosio 92 mg/dL" ])
    bubble = parse(role: "user", content: content)

    assert_equal "My results", bubble.at_css(".assistant-message__paragraph").text
    assert_match "Glucosio 92 mg/dL", bubble.at_css("details.assistant-message__photo-text pre").text
  end

  private

  def parse(**) = Nokogiri::HTML5.fragment(Views::Assistant::Chats::MessageBubble.new(**).call).at_css(".assistant-message")
end
