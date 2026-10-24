# frozen_string_literal: true

require "test_helper"

class Reports::Finance::DashboardTest < ActiveSupport::TestCase
  setup do
    today = Date.new(2025, 1, 20)
    @dashboard = Reports::Finance::Dashboard.new(
      audience: audience_for(profiles(:carol)), period: period(today - 29, today), today: today,
    )
  end

  test "builds each report once, the first time it is read" do
    %i[spending income cash_flow settlements attention].each do |name|
      assert_same @dashboard.public_send(name), @dashboard.public_send(name), name
    end
  end
end
