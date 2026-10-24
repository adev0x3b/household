# frozen_string_literal: true

# Units that are one unit spelled differently ("10^3/UL", "K/µL" → 10^3/µL,
# see Assistant::UnitName), one group per household and spelling: the row
# to keep (the canonical spelling, else the oldest) and the others, which
# Units::MergeDuplicates folds into it.
#
#   Units::Duplicates.groups.each { |group| Units::MergeDuplicates.call(group) }
module Units
  class Duplicates
    Group = Data.define(:name, :keep, :others)

    def self.groups
      Unit.order(:id).group_by { |unit| [ unit.household_id, Assistant::UnitName.key(unit.name) ] }.filter_map do |_key, units|
        next if units.one?

        name = Assistant::UnitName.normalize(units.first.name)
        keep = units.find { |unit| unit.name == name } || units.first
        Group.new(name: name, keep: keep, others: units - [ keep ])
      end
    end
  end
end
