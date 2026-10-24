# frozen_string_literal: true

require "test_helper"

# The page's one picker of quick emoji, and what each message's smile
# tells it.
class Views::Conversations::ReactionPickerTest < ActiveSupport::TestCase
  test "each quick emoji is a button giving that reaction, in a group that names itself" do
    picker = parse(Views::Conversations::ReactionPicker.new).at_css("#reaction_picker")
    emoji = picker.css("form button[type=submit]")

    assert_equal [ "group", I18n.t("conversations.reactions.add"), "post" ], [ picker["role"], picker["aria-label"], picker.at_css("form")["method"] ]
    assert_equal(MessageReaction::QUICK, emoji.map { _1["value"] })
    assert(emoji.all? { _1["name"] == "emoji" && _1["role"].nil? })
    assert_equal I18n.t("conversations.reactions.react_with", emoji: "👍"), emoji.first["aria-label"]
  end

  test "a message's smile names the message and where its reactions go, and opens from its own side" do
    alice, bob = profiles(:alice), profiles(:bob)
    message = send_message(Conversation.household_conversation(households(:example)), bob, "Bins tonight?")

    theirs = smile(message, viewer: alice)
    mine = smile(message, viewer: bob)

    url = Rails.application.routes.url_helpers.message_reaction_path(message)
    assert_equal url, theirs["data-reaction-picker-url-param"]
    assert_equal "message_#{message.id}", theirs["data-reaction-picker-message-param"]
    assert_equal [ "start", "end" ], [ theirs["data-reaction-picker-align-param"], mine["data-reaction-picker-align-param"] ]
    assert_equal [ "reaction-picker#open", "reaction_picker" ], [ theirs["data-action"], theirs["aria-controls"] ]
    assert_nil theirs["aria-haspopup"], "a disclosure, not an ARIA menu"
    assert_nil parse(Views::Conversations::Bubble.new(message: message, viewer: alice)).at_css(".reaction-picker"), "none of its own"
  end

  private

  def smile(message, viewer:)
    parse(Views::Conversations::Bubble.new(message: message, viewer: viewer)).at_css("button.message__tool")
  end

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
end
