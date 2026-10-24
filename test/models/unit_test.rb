# frozen_string_literal: true

require "test_helper"

class UnitTest < ActiveSupport::TestCase
  test "requires a name" do
    unit = Unit.new(name: nil)
    assert_not unit.valid?
    assert_includes unit.errors[:name], "can't be blank"
  end

  test "find_or_create_by_name returns the existing record for an exact match" do
    found = Unit.find_or_create_by_name("mg/dL", household_id: households(:example).id)
    assert_equal units(:mgdl), found
  end

  test "find_or_create_by_name is case-insensitive and whitespace-trimmed" do
    found = Unit.find_or_create_by_name("  MG/DL  ", household_id: households(:example).id)
    assert_equal units(:mgdl), found
  end

  test "find_or_create_by_name creates a new record when none matches" do
    assert_difference -> { Unit.count }, 1 do
      unit = Unit.find_or_create_by_name("ng/mL", household_id: households(:example).id)
      assert_equal "ng/mL", unit.name
    end
  end

  test "a name the household has already, in any case, is taken; the database holds it too" do
    duplicate = Unit.new(household: households(:example), name: "MG/DL") # fixture already has "mg/dL"

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "each household has its own units: the same name twice, and neither sees the other's" do
    theirs = Unit.find_or_create_by_name("mg/dL", household_id: households(:elsewhere).id)

    assert_not_equal units(:mgdl), theirs
    assert_includes Unit.accessible_by(profiles(:outsider)), theirs
    assert_not_includes Unit.accessible_by(profiles(:alice)), theirs
  end

  test "convert moves between units of the same family" do
    assert_in_delta(0.5, Unit.convert(500, Unit.new(name: "g"), Unit.new(name: "kg")).to_f)
    assert_equal 2500, Unit.convert(2.5, Unit.new(name: "l"), Unit.new(name: "ml")).to_f
  end

  test "convert refuses units from different families" do
    assert_nil Unit.convert(3, Unit.new(name: "g"), Unit.new(name: "pcs"))
    assert_nil Unit.convert(3, Unit.new(name: "pcs"), Unit.new(name: "kg"))
  end

  test "convert takes a missing unit at face value" do
    assert_equal 3, Unit.convert(3, nil, units(:kg))
    assert_equal 3, Unit.convert(3, units(:kg), nil)
  end

  test "a form offers the household's units by name, and no other household's" do
    elsewhere = Unit.create!(name: "drops", household: profiles(:outsider).household)
    names = Unit.names_for(profiles(:alice))

    # Plain lowercase names, so the order checked is the same in every
    # collation the database may sort them in.
    assert_equal %w[kg l pcs], names & %w[pcs kg l]
    assert_includes names, "mg/dL"
    assert_not_includes names, elsewhere.name
    assert_equal Unit.names_for(profiles(:alice)).zip(Unit.accessible_by(profiles(:alice)).order(:name).ids), Unit.choices_for(profiles(:alice))
  end
end
