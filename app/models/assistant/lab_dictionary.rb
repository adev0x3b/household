# frozen_string_literal: true

# The starter dictionary of analyte names (config/lab_analytes.yml): which
# names, in English, Italian or abbreviated, are the same analyte.
#
#   LabDictionary.same_test("Emoglobina")  # => #<Set {"hemoglobin", "haemoglobin", "hb", "hgb", …}>
#
# Names compare as `key`: lower case, no accents, punctuation as spaces
# ("25-OH Vitamina D" is "25 oh vitamina d").
module Assistant
  module LabDictionary
    PATH = Rails.root.join("config/lab_analytes.yml")

    module_function

    # Every key of the test `name` belongs to (itself included); empty when
    # the dictionary doesn't know it.
    def same_test(name) = groups.fetch(key(name), Set.new)

    def key(name) = TextMatch.fold(name).scan(/[[:alnum:]]+/).join(" ")

    def groups
      @groups ||= YAML.load_file(PATH).each_with_object({}) do |names, index|
        group = names.map { |name| key(name.to_s) }.to_set
        group.each do |name|
          raise ArgumentError, "#{PATH}: #{name.inspect} is in two groups" if index.key?(name)

          index[name] = group
        end
      end.freeze
    end
  end
end
