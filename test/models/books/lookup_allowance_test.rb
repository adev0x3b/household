# frozen_string_literal: true

require "test_helper"

# A household's book lookups for the day, counted in the cache.
class Books::LookupAllowanceTest < ActiveSupport::TestCase
  setup do
    @original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original }

  test "unlimited unless the installation sets a number, and then nothing is counted" do
    allowance = Books::LookupAllowance.new(households(:example))

    allowance.spend!

    assert_nil allowance.left
    assert_predicate allowance, :any_left?
  end

  test "each household spends its own, and a new day starts again" do
    with_env("BOOK_LOOKUPS_PER_DAY" => "2") do
      ours = Books::LookupAllowance.new(households(:example))
      2.times { ours.spend! }

      assert_equal 0, ours.left
      assert_not ours.any_left?
      assert_equal 2, Books::LookupAllowance.new(demo_household).left

      travel 1.day do
        assert_equal 2, ours.left
      end
    end
  end
end
