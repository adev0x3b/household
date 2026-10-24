# frozen_string_literal: true

require "test_helper"

class SetupCodes::RenewTest < ActiveSupport::TestCase
  test "a code is made while nobody exists, and only its digest is kept" do
    Household.find_each { |household| Households::Destroy.call(household) }

    result = SetupCodes::Renew.call

    assert_predicate result, :success?
    assert_match(/\A([A-HJ-NP-Z2-9]{4}-){3}[A-HJ-NP-Z2-9]{4}\z/, result.code)
    assert_equal SetupCode.digest(result.code), Platform::Setting.first.setup_code_digest
  end

  test "once anyone exists no code is made" do
    result = SetupCodes::Renew.call

    assert_equal :already_set_up, result.error
    assert_nil result.code
    assert_nil Platform.setup_code_digest
  end
end
