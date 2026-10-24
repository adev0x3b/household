# frozen_string_literal: true

require "test_helper"

class AnalyteTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:alice)
  end

  test "requires a name" do
    analyte = Analyte.new(profile: @profile, name: nil)
    assert_not analyte.valid?
    assert_includes analyte.errors[:name], "can't be blank"
  end

  test "a lab value's field suggests the person's own analytes, by name" do
    Analyte.create!(profile: profiles(:bob), name: "Ferritin")

    assert_equal %w[Cholesterol Glucose TSH], Analyte.names_for(@profile)
  end

  test "requires a profile" do
    analyte = Analyte.new(name: "Ferritin")
    assert_not analyte.valid?
    assert_includes analyte.errors[:profile], "must exist"
  end

  test "find_or_create_by_name returns the existing record for an exact match" do
    found = Analyte.find_or_create_by_name("Glucose", profile_id: @profile.id)
    assert_equal analytes(:glucose), found
  end

  test "find_or_create_by_name is case-insensitive and whitespace-trimmed" do
    found = Analyte.find_or_create_by_name("  glucose  ", profile_id: @profile.id)
    assert_equal analytes(:glucose), found
  end

  test "find_or_create_by_name creates a new record when none matches" do
    assert_difference -> { Analyte.count }, 1 do
      analyte = Analyte.find_or_create_by_name("Ferritin", profile_id: @profile.id)
      assert_equal "Ferritin", analyte.name
      assert_equal @profile, analyte.profile
    end
  end

  test "find_or_create_by_name returns nil for a blank name" do
    assert_nil Analyte.find_or_create_by_name("   ", profile_id: @profile.id)
  end

  test "a name it has already, in any case, is taken; the database holds it too" do
    duplicate = Analyte.new(profile: @profile, name: "glucose") # fixture already has "Glucose"

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "another profile can reuse an analyte name" do
    other = profiles(:bob)
    analyte = Analyte.create!(profile: other, name: "Glucose")
    assert_equal "Glucose", analyte.name
    assert_equal other, analyte.profile
  end
end
