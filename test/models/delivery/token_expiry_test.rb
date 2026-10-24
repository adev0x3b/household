# frozen_string_literal: true

require "test_helper"

# Delivery::TokenExpiry: what the console and the settings page say about
# the deploy token's end, from the date GitHub last gave.
class Delivery::TokenExpiryTest < ActiveSupport::TestCase
  test "nothing is known until GitHub has said" do
    expiry = Delivery::TokenExpiry.new(nil)

    assert_not expiry.known?
    assert_not expiry.soon?
    assert_not expiry.expired?
  end

  test "far off, near, and gone" do
    travel_to Time.zone.local(2026, 10, 20, 12) do
      far = Delivery::TokenExpiry.new(60.days.from_now)
      assert_predicate far, :known?
      assert_not far.soon?

      near = Delivery::TokenExpiry.new(3.days.from_now - 1.hour)
      assert_equal 3, near.days_left
      assert_predicate near, :soon?
      assert_not near.expired?

      gone = Delivery::TokenExpiry.new(1.hour.ago)
      assert_predicate gone, :expired?
      assert_predicate gone, :soon?
    end
  end

  test "the current one is what GitHub's headers last said" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Delivery::Github::EXPIRY_KEY, 5.days.from_now)

    assert_equal 5, Delivery::TokenExpiry.current.days_left
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end
end
