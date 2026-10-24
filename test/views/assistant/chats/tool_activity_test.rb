# frozen_string_literal: true

require "test_helper"

# A line for what the assistant did names the kind of record in everyday
# words, and a kind the app doesn't have as "a record".
class Views::Assistant::Chats::ToolActivityTest < ActiveSupport::TestCase
  test "a lookup names the kind of record it looked up" do
    assert_equal "Looked up: task", text_of("search_records", "tasks")
  end

  test "a kind the app doesn't have is a record" do
    assert_equal "Looked up: record", text_of("search_records", "spaceship")
  end

  test "a failed step says it didn't work" do
    assert_equal "Checked: record: didn't work", text_of("get_record", nil, ok: false)
  end

  private

  def text_of(tool, type, ok: true)
    component = Views::Assistant::Chats::ToolActivity.new(tool_name: tool, arguments: { type: type }, result: { ok: ok })
    Nokogiri::HTML5.fragment(component.call).at_css("span").text
  end
end
