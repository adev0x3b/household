# frozen_string_literal: true

# What the operations of one change set share while they are checked and
# applied. The catalogs are shared so that a lab result and a range, or a
# recipe and a grocery list, naming the same new analyte or ingredient
# create it once. supplies_bought maps each supply the set buys to its
# unit, because a dose's uses may name a supply before it exists.
module Assistant
  module ChangeSets
    Context = Struct.new(:profile, :chat, :acknowledged, :lab_catalog, :pantry_catalog, :resolver, :lab_units, :supplies_bought, keyword_init: true) do
      def self.for(set)
        new(profile: set.profile, chat: set.chat, acknowledged: set.acknowledged_warnings,
            lab_catalog: LabCatalog.new(set.profile), pantry_catalog: PantryCatalog.new(set.profile),
            resolver: Resolver.new(set.profile, chat: set.chat), lab_units: {}, supplies_bought: {})
      end

      # A record someone shared with the user keeps naming its owner's
      # analytes and ingredients, never the user's own.
      def lab_catalog_for(owner)
        owner == profile ? lab_catalog : ((@lab_catalogs ||= {})[owner.id] ||= LabCatalog.new(owner))
      end

      def pantry_catalog_for(owner)
        owner == profile ? pantry_catalog : ((@pantry_catalogs ||= {})[owner.id] ||= PantryCatalog.new(owner))
      end
    end
  end
end
