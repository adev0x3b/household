# frozen_string_literal: true

require "test_helper"

# One analyte per lab test, whatever language or abbreviation the report
# uses; duplicates the user points out are merged, and the old name stays
# as an alias.
class Assistant::AnalyteNamesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  def catalog = Assistant::LabCatalog.new(@profile)
  def analyte(name) = Analyte.create!(profile: @profile, name: name)
  def apply(result) = Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)

  test "the dictionary's names of one test find the analyte already saved" do
    hemoglobin = analyte("Hemoglobin")
    vitamin_d = analyte("Vitamina D")

    assert_equal hemoglobin, catalog.analyte("Emoglobina")
    assert_equal hemoglobin, catalog.analyte("HGB")
    assert_equal vitamin_d, catalog.analyte("25-OH Vitamin D")
    assert_equal "Globuli bianchi", catalog.analyte("Globuli bianchi").name, "a test nobody has yet keeps the report's wording"
  end

  test "the dictionary keeps different tests apart even when the words overlap" do
    cholesterol = @profile.analytes.find_by!(name: "Cholesterol")
    hemoglobin = analyte("Emoglobina")

    assert_predicate catalog.analyte("HDL Cholesterol"), :new_record?
    assert_predicate catalog.analyte("Emoglobina glicata"), :new_record?
    assert_equal cholesterol, catalog.analyte("Colesterolo totale")
    assert_equal hemoglobin, catalog.analyte("Hb")
  end

  test "an OCR'd Italian report saves onto the English analytes" do
    hemoglobin = analyte("Hemoglobin")
    before = @profile.analytes.count

    result = run_tool(:record_lab_results, @chat, date: "today", values: [ { analyte: "Emoglobina", value: "13.5", unit: "g/dL" },
                                                                           { analyte: "Glicemia", value: "92", unit: "mg/dl" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal before, @profile.analytes.count
    assert_equal [ "Glucose", "Hemoglobin" ], days_of(LabTestResult, @profile).sole
      .lab_test_result_entries.map { |e| e.analyte.name }.sort
    assert_equal hemoglobin, LabTestResultEntry.find_by!(value: "13.5").analyte
  end

  test "merging two analytes waits for the button, moves values and ranges, and keeps the old name as an alias" do
    AssistantEval::Seeds.two_lab_reports(@profile)
    short = analyte("Vit D")
    long = analyte("Vitamin D")
    unit = Unit.create!(household: @profile.household, name: "ng/mL")
    ReferenceRange.create!(analyte: short, unit: unit, sex: "any", low: 30, high: 100)
    ReferenceRange.create!(analyte: long, unit: unit, sex: "any", low: 20, high: 80)
    result = LabTestResult.create!(profile: @profile, title: "Lab results", starts_on: Date.new(2026, 9, 10)).first_occurrence
    result.lab_test_result_entries.build(analyte: short, unit: unit, value: "25")
    result.save!

    merge = run_tool(:update_record, @chat, type: "analyte", ref: "Vit D", merge_into: "Vitamin D")
    assert_equal "waiting_for_user", merge[:data][:status], merge.inspect
    assert Analyte.exists?(short.id)

    apply(merge)
    assert_not Analyte.exists?(short.id)
    assert_equal long, result.lab_test_result_entries.sole.reload.analyte
    assert_equal [ 20 ], long.reference_ranges.pluck(:low).map(&:to_i), "the kept analyte's range wins"
    assert_equal [ "Vit D" ], long.aliases.pluck(:name)
    assert_not Assistant::ChangeSet.find(merge[:data][:change_set_id]).undoable?
    assert_equal long, catalog.analyte("vit d")
  end

  test "merging refuses unknown names and an analyte into itself, naming what there is" do
    analyte("Vitamin D")

    unknown = run_tool(:update_record, @chat, type: "analyte", ref: "Vitamin Q", merge_into: "Vitamin D")
    assert_match(/no analyte called Vitamin Q; the user's include .*Vitamin D/, unknown.inspect)

    same = run_tool(:update_record, @chat, type: "analyte", ref: "vitamin d", merge_into: "Vitamin D")
    assert_match(/same analyte already/, same.inspect)
  end

  test "an alias can't be one of the profile's analyte names" do
    vitamin_d = analyte("Vitamin D")
    analyte("TSH 2")

    assert_not AnalyteAlias.new(analyte: vitamin_d, name: "tsh 2").valid?
    assert_predicate AnalyteAlias.new(analyte: vitamin_d, name: "Vit D"), :valid?
  end

  test "the dictionary never puts a name in two groups" do
    keys = YAML.load_file(Assistant::LabDictionary::PATH).flatten.map { |name| Assistant::LabDictionary.key(name.to_s) }
    assert_equal keys.size, keys.uniq.size, keys.tally.select { |_, n| n > 1 }.keys.inspect
  end
end
