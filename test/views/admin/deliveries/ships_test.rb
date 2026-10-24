# frozen_string_literal: true

require "test_helper"

# The commits a press would ship, newest first and folded past SHOWN.
class Views::Admin::Deliveries::ShipsTest < ActiveSupport::TestCase
  test "nothing to ship says so" do
    assert_equal "Nothing new ships: it already runs this version.", parse([]).at_css(".report-hint").text
  end

  test "the newest come first, and the oldest past SHOWN are counted, not listed" do
    commits = (1..10).map { |n| Delivery::Github::Commit.new(sha: format("%040x", n), title: "Commit #{n}", author: "adev", committed_at: Time.current, html_url: nil) }
    html = parse(commits)

    assert_equal "10 commits ship:", html.at_css(".deployment-modal__line").text
    assert_equal [ "Commit 10", "Commit 9" ], html.css(".deployment-modal__commits li span:last-child").first(2).map(&:text)
    assert_equal Views::Admin::Deliveries::Ships::SHOWN, html.css(".deployment-modal__commits li .report-mono").size
    assert_equal "and 2 more", html.at_css(".deployment-modal__commits li.report-hint").text
  end

  private

  def parse(commits) = Nokogiri::HTML5.fragment(Views::Admin::Deliveries::Ships.new(commits).call)
end
