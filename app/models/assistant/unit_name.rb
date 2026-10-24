# frozen_string_literal: true

# One spelling per lab unit, whatever the report, the OCR or the model wrote:
#
#   UnitName.normalize("10% 3/uL")  # => "10^3/µL"
#   UnitName.normalize("104 6/UL")  # => "10^6/µL"
#   UnitName.normalize("K/uL")      # => "10^3/µL"
#   UnitName.normalize("mcg/dl")    # => "µg/dL"
#   UnitName.normalize("UI/L")      # => "U/L"
#
# Fixes the shapes an exponent comes out of OCR in (10^3, 10³, 10E3, x10*3,
# "10% 3", "10° 3"), micro (u, mc and the Greek μ all become µ), spacing and
# letter case, and maps synonyms (K/µL is 10^3/µL; IU and UI per litre are
# enzyme units, U/L). Anything it doesn't recognize comes back squished, not
# guessed at. `key` is what two spellings of one unit share, so an existing
# unit is found by it.
module Assistant
  module UnitName
    # Canonical case of the units lab reports use, by lower-case spelling.
    CANONICAL = [
      "%", "g/dL", "g/L", "mg/dL", "mg/L", "µg/dL", "µg/L", "ng/mL", "ng/dL", "ng/L", "pg/mL", "pg", "fL", "g",
      "mmol/L", "µmol/L", "nmol/L", "pmol/L", "mmol/mol", "mEq/L", "U/L", "mU/L", "IU/mL", "mIU/L", "mIU/mL", "µIU/mL",
      "µU/mL", "10^3/µL", "10^6/µL", "10^9/L", "10^12/L", "mm/h", "mmHg", "sec", "mL/min", "mL/min/1.73m²"
    ].index_by(&:downcase).freeze

    SYNONYMS = {
      "k/µl" => "10^3/µL", "m/µl" => "10^6/µL", "10^3/mm^3" => "10^3/µL", "10^6/mm^3" => "10^6/µL",
      "ui/l" => "U/L", "iu/l" => "U/L", "mui/l" => "mIU/L", "mui/ml" => "mIU/mL", "µui/ml" => "µIU/mL"
    }.freeze

    SUPERSCRIPTS = { "²" => "2", "³" => "3", "⁶" => "6", "⁹" => "9", "¹" => "1", "⁰" => "0" }.freeze

    module_function

    def normalize(name)
      text = name.to_s.squish.tr("μ", "µ").gsub(/\s*\/\s*/, "/")
      return if text.empty?

      text = exponent(text)
      text = text.gsub(/(?<![[:alpha:]])(?:u|mc)(?=(?:g|l|iu|ui|mol|u)(?![[:alpha:]]))/i, "µ")
      SYNONYMS[text.downcase] || CANONICAL[text.downcase] || text
    end

    def key(name) = normalize(name)&.downcase

    # The unit the user wrote for `analyte` in `text`: the one known unit
    # with a slash ("pg/mL", "10^3/uL") in the sentence that names it, as in
    # "the references for Cobalamin in pg/mL are 150 to 250". None, or two
    # different ones, is nil: better asked than guessed.
    def said_for(text, analyte)
      name = TextMatch.fold(analyte).squish
      return if name.empty?

      units = text.to_s.split(/(?<=[.;!?])\s+|\n+/).select { |sentence| TextMatch.fold(sentence).include?(name) }.flat_map do |sentence|
        sentence.split(/[\s,:()]+/).filter_map do |token|
          unit = normalize(token.delete_suffix("."))
          unit if unit&.include?("/") && (CANONICAL.value?(unit) || SYNONYMS.value?(unit))
        end
      end
      units.uniq.one? ? units.first : nil
    end

    # 10³, 10E3, x10^3, 10*3, 10**3, "10% 3" and "10° 3" all mean 10^3. In
    # "104 6/UL" OCR read the caret as a 4, so it means 10^6.
    def exponent(text)
      text = text.gsub(/10([²³⁶⁹¹⁰]+)/) { "10^#{$1.chars.map { |c| SUPERSCRIPTS[c] }.join}" }
      text = text.sub(/\A104\s+(\d{1,2})(?=\/)/) { "10^#{$1}" }
      text.sub(/\A(?:x\s*)?10\s*(?:\^|\*{1,2}|%|°|e)\s*(\d{1,2})(?=\/|\z)/i) { "10^#{$1}" }
    end
  end
end
