# frozen_string_literal: true

require "test_helper"

class Components::NoticeTest < ActiveSupport::TestCase
  test "what went wrong is announced; news and a call to act are not" do
    assert_equal "alert", parse(Components::Notice.new(tone: :critical))["role"]
    assert_nil parse(Components::Notice.new(tone: :action))["role"]
    assert_equal %w[notice notice--neutral], parse(Components::Notice.new).classes
  end

  test "a tone it doesn't have is a mistake rather than news" do
    assert_raises(ArgumentError) { Components::Notice.new(tone: :warning) }
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call { "Read me" }).at_css(".notice")
end
