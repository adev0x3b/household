# frozen_string_literal: true

module GroceryLists
  # What someone types into a list's quick-add bar, read as an item:
  #
  #   "2 kg flour" / "flour 2 kg" / "2kg flour" / "1,5 l milk"  → quantity, unit, name
  #   "6 eggs" / "eggs 6"                                       → quantity, name
  #   "flour"                                                   → name
  #
  # A quantity is a number at the start or the end (decimal comma or point).
  # The word next to it is a unit only when the household knows it (or it is
  # one of Unit::FAMILIES, so g/kg/ml/l work before anyone has typed them);
  # otherwise it belongs to the name ("6 eggs"). Nothing is created here: the
  # item's `ingredient_name=` / `unit_name=` do that when it is saved.
  class ParseItem
    Result = Data.define(:name, :quantity, :unit_name)

    NUMBER = /\A\d+(?:[.,]\d+)?\z/
    NUMBER_WITH_UNIT = /\A(\d+(?:[.,]\d+)?)([[:alpha:]]+)\z/

    def self.call(text, unit_names:) = new(unit_names).call(text)

    def initialize(unit_names)
      @units = (Array(unit_names) + Unit::FAMILIES.keys).map { |name| name.to_s.strip.downcase }.to_set
    end

    def call(text)
      words = text.to_s.squish.split(" ")
      return Result.new(name: "", quantity: nil, unit_name: nil) if words.empty?

      quantity, unit, rest = take_quantity(words)
      Result.new(name: rest.join(" "), quantity: quantity, unit_name: unit)
    end

    private

    # [quantity, unit, remaining words]
    def take_quantity(words)
      if (match = NUMBER_WITH_UNIT.match(words.first)) && unit?(match[2])
        return [ number(match[1]), match[2], words.drop(1) ]
      end
      if (match = NUMBER_WITH_UNIT.match(words.last)) && unit?(match[2]) && words.size > 1
        return [ number(match[1]), match[2], words[0...-1] ]
      end
      return split_at(words, 0) if NUMBER.match?(words.first) && words.size > 1
      return split_at(words, words.size - 1) if NUMBER.match?(words.last) && words.size > 1
      return split_at(words, words.size - 2) if words.size > 2 && NUMBER.match?(words[-2]) && unit?(words.last)

      [ nil, nil, words ]
    end

    # The number sits at `index`; a known unit right after it comes along.
    def split_at(words, index)
      rest = words.dup
      quantity = number(rest.delete_at(index))
      unit = rest[index] if rest[index] && unit?(rest[index])
      rest.delete_at(index) if unit
      [ quantity, unit, rest ]
    end

    def unit?(word) = @units.include?(word.downcase)
    def number(text) = BigDecimal(text.tr(",", "."))
  end
end
