# frozen_string_literal: true

require "test_helper"

# Whether dev's branch can merge, worded the same on the dev card and in the
# merge modal.
class Views::Admin::Deliveries::MergeBadgeTest < ActiveSupport::TestCase
  test "every state the pipeline can answer has a tone, an icon and words" do
    badges = Views::Admin::Deliveries::MergeBadge::LOOKS.keys.to_h { |state| [ state, parse(state).at_css(".status-badge") ] }

    assert_equal %w[status-badge--good], badges[:ready]["class"].split.grep(/--/)
    assert_equal %w[status-badge--critical], badges[:ci_failed]["class"].split.grep(/--/)
    assert_includes badges[:ci_running].at_css("i")["class"], "fa-spin"
    assert_equal "No pull request", badges[:none].text
    badges.each { |state, badge| assert_predicate badge.text, :present?, state }
  end

  test "a state there isn't is a mistake, not a blank badge" do
    assert_raises(KeyError) { parse(:sideways) }
  end

  private

  def parse(state) = Nokogiri::HTML5.fragment(Views::Admin::Deliveries::MergeBadge.new(state: state).call)
end
