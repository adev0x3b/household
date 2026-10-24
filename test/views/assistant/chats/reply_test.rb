# frozen_string_literal: true

require "test_helper"

class Views::Assistant::Chats::ReplyTest < ActiveSupport::TestCase
  test "before its first words, a screen reader hears that the assistant is thinking, and the dots are for the eye" do
    reply = parse(text: nil)

    assert_equal "status", reply["role"]
    assert_equal I18n.t("assistant.thread.thinking"), reply.at_css(".is-sr-only").text
    assert_equal 3, reply.css(".assistant-message__dot[aria-hidden=true]").size
  end

  test "the words written so far are kept out of the log's announcements, which read the finished answer once" do
    reply = parse(text: "Booked for Tuesday")

    assert_equal "off", reply["aria-live"]
    assert_nil reply["role"]
    assert_equal "Booked for Tuesday", reply.at_css(".assistant-message__paragraph").text
  end

  private

  def parse(text:)
    Nokogiri::HTML5.fragment(Views::Assistant::Chats::Reply.new(text: text).call).at_css("##{Views::Assistant::Chats::Reply::ID}")
  end
end
