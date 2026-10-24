# frozen_string_literal: true

# A spoken name resolved to the profile's analyte or the household's unit,
# or to a new unsaved one written only when its owner is saved. One catalog
# serves a whole change set, so a value's unit and its range's unit are the
# same row: LabTestResultEntry#flag needs that to find the range.
module Assistant
  class LabCatalog
    def initialize(profile)
      @profile = profile
      @new_analytes = {}
      @new_units = {}
    end

    def analyte(name)
      name = name.to_s.squish
      return if name.empty?

      known_analyte(name) || @new_analytes[name.downcase] ||= Analyte.new(profile: @profile, name: name)
    end

    # The profile's analyte `name` means: its own name, a name it had before
    # a merge, another name of the same test ("Emoglobina" is the saved
    # "Hemoglobin"), then a close spelling. A close spelling doesn't count
    # when the dictionary knows the two are different tests ("HDL
    # Cholesterol" is not the saved "Cholesterol").
    def known_analyte(name)
      analytes = @profile.analytes
      NameMatch.new(analytes, name).exact ||
        AnalyteAlias.where(profile: @profile).where("unaccent(lower(name)) = unaccent(lower(?))", name).first&.analyte ||
        same_test(name) ||
        NameMatch.find(analytes, name)&.then { |close| close unless different_tests?(name, close.name) }
    end

    # Units are compared spelled one way (Assistant::UnitName), so "10^3/uL",
    # "K/µL" and an existing "10^3/UL" are one unit: the existing row, with
    # the canonical spelling preferred when duplicates remain.
    def unit(name)
      name = UnitName.normalize(name)
      return if name.nil?

      key = name.downcase
      @units ||= Unit.accessible_by(@profile).group_by { |unit| UnitName.key(unit.name) }
      @units[key]&.min_by { |unit| [ unit.name == name ? 0 : 1, unit.id ] } || @new_units[key] ||= Unit.new(name: name, household_id: @profile.household_id)
    end

    def new_analyte_names = @new_analytes.values.map(&:name)
    def new_unit_names = @new_units.values.map(&:name)

    private

    # The analyte whose name (or alias) the dictionary puts in the same test;
    # the older one while two of them aren't merged yet.
    def same_test(name)
      LabDictionary.same_test(name).filter_map { |key| by_dictionary_key[key] }.first
    end

    def different_tests?(said, known)
      said = LabDictionary.same_test(said)
      known = LabDictionary.same_test(known)
      said.any? && known.any? && said != known
    end

    def by_dictionary_key
      @by_dictionary_key ||= @profile.analytes.includes(:aliases).order(id: :desc).each_with_object({}) do |analyte, index|
        [ analyte.name, *analyte.aliases.map(&:name) ].each { |n| index[LabDictionary.key(n)] = analyte }
      end
    end
  end
end
