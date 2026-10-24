# frozen_string_literal: true

require "test_helper"

class ReferenceRangeTest < ActiveSupport::TestCase
  test "requires at least one bound" do
    range = ReferenceRange.new(analyte: analytes(:tsh), unit: units(:miul), sex: :any)
    assert_not range.valid?
    assert range.errors.of_kind?(:base, :blank_bounds)
  end

  test "is valid with only a high bound" do
    range = ReferenceRange.new(analyte: analytes(:tsh), unit: units(:miul), sex: :any, high: 5.7)
    assert_predicate range, :valid?
  end

  test "enforces uniqueness scoped to analyte, unit, and sex" do
    duplicate = ReferenceRange.new(
      analyte: analytes(:glucose), unit: units(:mgdl), sex: :any, low: 1, high: 2
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sex], "has already been taken"
  end

  test "allows the same analyte and unit with a different sex" do
    range = ReferenceRange.new(analyte: analytes(:glucose), unit: units(:mgdl), sex: :female, low: 70, high: 100)
    assert_predicate range, :valid?
  end

  test "low must be less than high" do
    range = ReferenceRange.new(analyte: analytes(:tsh), unit: units(:miul), sex: :any, low: 5, high: 5)
    assert_not range.valid?
    assert_includes range.errors[:low], "must be less than high"
  end

  test "critical_low must not exceed low" do
    range = ReferenceRange.new(analyte: analytes(:tsh), unit: units(:miul), sex: :any, low: 5, high: 10, critical_low: 6)
    assert_not range.valid?
    assert_includes range.errors[:critical_low], "must be less than low"
  end

  test "critical_high must not be below high" do
    range = ReferenceRange.new(analyte: analytes(:tsh), unit: units(:miul), sex: :any, low: 5, high: 10, critical_high: 9)
    assert_not range.valid?
    assert_includes range.errors[:critical_high], "must be greater than high"
  end

  test "sex enum values" do
    assert_equal({ "any" => 0, "male" => 1, "female" => 2 }, ReferenceRange.sexes)
  end
end
