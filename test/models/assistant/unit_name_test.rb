# frozen_string_literal: true

require "test_helper"

# One lab unit, one row: OCR shapes and synonyms of a unit never create a new
# one, and the duplicates already saved can be merged.
class Assistant::UnitNameTest < ActiveSupport::TestCase
  test "OCR shapes, micro, case and synonyms come out one way" do
    {
      "10^3/uL" => "10^3/µL", "10% 3/uL" => "10^3/µL", "10° 3/UL" => "10^3/µL", "10³/µl" => "10^3/µL",
      "x10E3/uL" => "10^3/µL", "104 6/UL" => "10^6/µL", "104 3/uL" => "10^3/µL", "10*3 / uL" => "10^3/µL", "K/uL" => "10^3/µL", "M/μL" => "10^6/µL",
      "10^9/l" => "10^9/L", "mcg/dl" => "µg/dL", "uIU/ml" => "µIU/mL", "UI/L" => "U/L", "IU/L" => "U/L",
      "MG/DL" => "mg/dL", "U/L" => "U/L", "mU/L" => "mU/L", "%" => "%", "  ng / mL " => "ng/mL",
      "cells/hpf" => "cells/hpf"
    }.each { |said, expected| assert_equal expected, Assistant::UnitName.normalize(said), said }
    assert_nil Assistant::UnitName.normalize(" ")
  end

  test "the catalog finds an existing unit by any spelling, preferring the canonical one" do
    old = Unit.create!(household: households(:example), name: "10^3/UL")
    catalog = Assistant::LabCatalog.new(profiles(:alice))

    assert_equal old, catalog.unit("K/uL")
    assert_equal old, catalog.unit("10% 3/uL")

    canonical = Unit.create!(household: households(:example), name: "10^3/µL")
    assert_equal canonical, Assistant::LabCatalog.new(profiles(:alice)).unit("10^3/UL")
  end

  test "a unit nobody has yet is created with the canonical spelling" do
    unit = Assistant::LabCatalog.new(profiles(:alice)).unit("x10E9/l")

    assert_predicate unit, :new_record?
    assert_equal "10^9/L", unit.name
  end

  test "duplicates merge into the canonical spelling, leaving a colliding range where it is" do
    profile = profiles(:alice)
    wbc = Analyte.create!(profile: profile, name: "WBC")
    plt = Analyte.create!(profile: profile, name: "PLT")
    upper = Unit.create!(household: households(:example), name: "10^3/UL")
    kilo = Unit.create!(household: households(:example), name: "K/µL")
    ReferenceRange.create!(analyte: wbc, unit: upper, sex: "any", low: 4, high: 10)
    colliding = ReferenceRange.create!(analyte: wbc, unit: kilo, sex: "any", low: 4.5, high: 11)
    ReferenceRange.create!(analyte: plt, unit: kilo, sex: "any", low: 150, high: 400)
    result = LabTestResult.create!(profile: profile, title: "Blood count", starts_on: Date.new(2026, 9, 1)).first_occurrence
    result.lab_test_result_entries.build(analyte: plt, unit: kilo, value: "250")
    result.save!

    group = Units::Duplicates.groups.find { |g| g.name == "10^3/µL" }
    assert_equal upper, group.keep
    merged = Units::MergeDuplicates.call(group)

    assert_equal "10^3/µL", upper.reload.name
    assert_equal [ 1, 1, [ colliding ] ], [ merged.rows, merged.ranges, merged.collisions ]
    assert_equal upper, result.lab_test_result_entries.sole.reload.unit
    assert Unit.exists?(kilo.id), "the unit still holding a range stays"
  end

  test "the unit written next to an analyte's name, only when it's clear" do
    said = "My doctor said the references for Cobalamin in pg/mL are 150 low 250 high. Vitamin D is good between 20 and 50.\n" \
           "WBC 4-10 10^3/uL or K/uL. Ferritin 30 ng/mL, maybe 30 µg/L."

    assert_equal "pg/mL", Assistant::UnitName.said_for(said, "Cobalamin")
    assert_equal "10^3/µL", Assistant::UnitName.said_for(said, "WBC"), "two spellings of one unit are one unit"
    assert_nil Assistant::UnitName.said_for(said, "Vitamin D"), "no unit said"
    assert_nil Assistant::UnitName.said_for(said, "Ferritin"), "two different units"
    assert_nil Assistant::UnitName.said_for(said, "Calcium")
    assert_nil Assistant::UnitName.said_for(said, " "), "no analyte named"
  end
end
