# frozen_string_literal: true

require "test_helper"

class Views::Assistant::Chats::MarkdownTest < ActiveSupport::TestCase
  test "blank lines split paragraphs, and a single line break stays inside one" do
    text = parse("Saved your appointment.\nIt is on Tuesday.\n\nAnything else?")

    paragraphs = text.css("p.assistant-message__paragraph")
    assert_equal [ "Saved your appointment.It is on Tuesday.", "Anything else?" ], paragraphs.map(&:text)
    assert_equal 1, paragraphs.first.css("br").size
  end

  test "a run of dashed or numbered lines is a list, between the lines around it" do
    text = parse("Two tasks match:\n- Bins\n* Dishes\n1. Laundry\nWhich one?")

    assert_equal [ "p", "ul", "p" ], text.element_children.map(&:name)
    assert_equal [ "Bins", "Dishes", "Laundry" ], text.css("ul.assistant-message__list li").map(&:text)
  end

  test "words between double asterisks are bold, and a lone pair is text" do
    text = parse("Take **two** tablets, not ** one.")

    assert_equal [ "two" ], text.css("strong").map(&:text)
    assert_equal "Take two tablets, not ** one.", text.text
  end

  test "markup in a reply is shown as text, never as HTML" do
    text = parse("<script>alert(1)</script> **<b>hi</b>**")

    assert_empty text.css("script, b")
    assert_equal "<b>hi</b>", text.at_css("strong").text
  end

  private

  def parse(text) = Nokogiri::HTML5.fragment(Views::Assistant::Chats::Markdown.new(text).call)
end
