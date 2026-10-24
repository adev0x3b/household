# frozen_string_literal: true

require "test_helper"

class Components::Report::StatusCardTest < ActiveSupport::TestCase
  test "the card's edge takes a status's tone, and a tone there isn't is a mistake" do
    card = Nokogiri::HTML5.fragment(Components::Report::StatusCard.new(tone: :critical, action: true).call).at_css("div")

    assert_equal %w[report-status report-status--critical report-status--action], card.classes
    assert_raises(ArgumentError) { Components::Report::StatusCard.new(tone: :amber) }
  end
end
