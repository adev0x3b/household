# frozen_string_literal: true

require "test_helper"

# Which day, and which dose of it, a linked housemate's request is about.
class Views::Links::ApprovalRowTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    link!(@alice, @bob)
    @day = Date.new(2026, 3, 9)
  end

  test "a request about one dose names the day and the time of that dose" do
    series = series!("Medication", profile: @alice, starts_on: @day, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    approval = Links::Approvals::Hold.call(requester: @bob, record: series.occurrence_on(@day, time: "20:00"), kind: :complete)

    assert_includes facts(approval), "#{I18n.l(@day, format: :long)} #{I18n.t("medications.at_time", time: "20:00")}"
  end

  test "a request about a day without a time names the day alone" do
    approval = Links::Approvals::Hold.call(requester: @bob, record: events(:water_the_plants).occurrence_on(@day), kind: :complete)

    assert_includes facts(approval), I18n.l(@day, format: :long)
  end

  private

  def facts(approval)
    row = Nokogiri::HTML5.fragment(ApplicationController.render(Views::Links::ApprovalRow.new(approval: approval, viewer: @alice), layout: false))
    row.at_css(".household__facts").css("span").map(&:text)
  end
end
