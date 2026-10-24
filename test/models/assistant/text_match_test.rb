# frozen_string_literal: true

require "test_helper"

# Typos, OCR slips and missing accents still find the record; names that
# merely look alike ("HDL" / "LDL") never stand in for each other.
class Assistant::TextMatchTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
  end

  teardown { travel_back }

  def analyte(name) = Analyte.create!(profile: @profile, name: name)
  def search(type, query, **options) = Assistant::Resources.fetch(type).search(@profile, query: query, **options)

  test "typo? allows a small edit of a long word, never of a short one" do
    assert Assistant::TextMatch.typo?("Coba1amin", "Cobalamin")
    assert Assistant::TextMatch.typo?("eritroci", "Eritrociti")
    assert Assistant::TextMatch.typo?("Marko", "Marco")
    assert Assistant::TextMatch.typo?("unita", "Unità")
    assert_not Assistant::TextMatch.typo?("HDL Cholesterol", "LDL Cholesterol")
    assert_not Assistant::TextMatch.typo?("Free T3", "Free T4")
    assert_not Assistant::TextMatch.typo?("Vitamin B12", "Vitamin B6")
    assert_not Assistant::TextMatch.typo?("Estriol", "Cobalamin")
  end

  test "a search leaves out the words that name nothing, unless they are all it was given" do
    task!(profile: @profile, date: Date.current, title: "Water the plants")
    task!(profile: @profile, date: Date.current, title: "Pulizia della cantina")

    assert_empty search("task", "Repot the basil", date_from: Date.current, date_to: Date.current), "\"the\" is in every title"
    assert_empty search("task", "Ritirare il pacco di Marco", date_from: Date.current, date_to: Date.current)
    assert_equal([ "Water the plants" ], search("task", "water the ferns", date_from: Date.current, date_to: Date.current).map { _1[:title] })
    assert_equal([ "Water the plants" ], search("task", "the", date_from: Date.current, date_to: Date.current).map { _1[:title] })
    assert_empty search("task", "x", date_from: Date.current, date_to: Date.current), "a lone letter names nothing, so finds nothing"
  end

  test "close Italian and English spellings of the same test count as one" do
    assert Assistant::TextMatch.typo?("Emoglobina", "Hemoglobin")
    assert Assistant::TextMatch.typo?("Creatinina", "Creatinine")
  end

  test "a name resolves through a typo or a missing accent" do
    cobalamin = analyte("Cobalamin")
    unita = analyte("Unità")

    assert_equal cobalamin, Assistant::NameMatch.find(@profile.analytes, "Coba1amin")
    assert_equal cobalamin, Assistant::NameMatch.find(@profile.analytes, "COBALAMIN")
    assert_equal unita, Assistant::NameMatch.find(@profile.analytes, "unita")
  end

  test "a lookalike name is a new row, and two close rows are a question, not a guess" do
    analyte("Colesterolo LDL")
    assert_nil Assistant::NameMatch.find(@profile.analytes, "Colesterolo HDL")

    analyte("Eritrociti")
    analyte("Eritrocita")
    assert_nil Assistant::NameMatch.find(@profile.analytes, "Eritrocit")
  end

  test "short words count: a different letter or number is a different name" do
    vitamin_d = analyte("Vitamin D")
    analyte("Free T4")

    assert_nil Assistant::NameMatch.find(@profile.analytes, "Vitamin Q")
    assert_nil Assistant::NameMatch.find(@profile.analytes, "Vitamin B12")
    assert_nil Assistant::NameMatch.find(@profile.analytes, "Free T3")
    assert_equal vitamin_d, Assistant::NameMatch.find(@profile.analytes, "vitamin d")
  end

  test "supplies resolve through a typo" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    assert_equal "Syringes", Assistant::SupplyUses.new(@profile, [ { "supply" => "Syrenges", "quantity" => 1 } ]).pairs.sole.first.name
  end

  test "a household member through a misspelled name" do
    marco = AssistantEval::Seeds.household_member(@profile)

    assert_equal marco, Assistant::Members.new(@profile).resolve("Marko").profile
  end

  test "search: exact words first, accent-blind; close spellings only when nothing matches" do
    AssistantEval::Seeds.two_lab_reports(@profile)
    AssistantEval::Seeds.b12_injection_series(@profile)
    Occurrences::Create.call(Task.new(title: "Rinnovo tessera sanità", starts_on: Date.new(2026, 9, 25)), by: @profile)

    assert_equal([ "Rinnovo tessera sanità" ], search("task", "sanita").map { _1[:title] })
    assert_equal([ Date.new(2026, 9, 16).iso8601 ], search("lab_test_result", "coba1amin").map { _1[:date] })
    assert_equal([ "Cobalamin injection" ], search("medication", "coba1amin", date_from: Date.new(2026, 9, 3), date_to: Date.new(2026, 9, 3)).map { _1[:title] })
    assert_empty search("task", "colonoscopy")
    assert_empty search("medication", "ldl")
  end

  test "search ranks the closer spelling first" do
    [ "Syringe caps", "Syringes" ].each { |name| Supply.create!(profile: @profile, name: name, category: :consumable, unit_label: "pieces") }

    assert_equal([ "Syringes", "Syringe caps" ], search("supply", "syringess").map { _1[:name] })
  end
end
