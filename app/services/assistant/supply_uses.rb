# frozen_string_literal: true

module Assistant
  # The supplies a dose uses ("one needle and one syringe"), as [supply,
  # quantity] pairs. A supply nobody bought is reported, never created,
  # because stock only exists once something was bought. The one exception
  # is a supply the same change set buys: it waits as pending and is found
  # once that purchase is saved.
  #
  #   uses = SupplyUses.new(profile, [{ "supply" => "needle", "quantity" => 1 }])
  #   uses.pairs    # => [[#<Supply Needles>, 1]]
  #   uses.list!    # => [[supply_id, 1]], while applying
  class SupplyUses
    NAME_KEYS = %w[supply name item].freeze
    QUANTITY_KEYS = %w[quantity qty amount count].freeze

    attr_reader :pairs, :unknown, :pending

    def initialize(profile, raw, bought: {})
      @profile = profile
      @pairs = []
      @unknown = []
      @pending = []
      @bought = bought.to_h
      entries(raw).each do |name, quantity|
        if (supply = find(name)) then @pairs << [ supply, quantity ]
        elsif bought_name(name) then @pending << [ name, quantity ]
        else @unknown << name
        end
      end
    end

    # The medication is a supply too: "0.12 ml of cobalamin" is the dose and
    # what the vial loses. A supply named like the medication and kept in the
    # dose's unit is added by the dose's quantity, because models list the
    # syringe and the needle and leave the vial out. Returns self.
    def include_dose!(name, quantity, unit)
      return self if name.blank? || quantity.blank? || unit.blank?

      quantity = quantity.to_s.tr(",", ".").to_d
      if (supply = find(name.to_s.squish))
        @pairs << [ supply, quantity ] if same_unit?(supply.unit_label, unit) && @pairs.none? { |listed, _| listed.id == supply.id }
      elsif same_unit?(bought_unit(name), unit) && @pending.none? { |listed, _| variants(listed).intersect?(variants(name)) }
        @pending << [ name.to_s.squish, quantity ]
      end
      self
    end

    def any? = @pairs.any? || @pending.any? || @unknown.any?
    def pending? = @pending.any?

    # The pending ones as pairs, once their purchase is saved; call it while
    # applying.
    def pending_pairs!
      @pending.map do |name, quantity|
        supply = find(name)
        raise Failure, "no supply called #{name} was saved — record the purchase first, or leave it out" unless supply

        [ supply, quantity ]
      end
    end

    def pairs! = @pairs + pending_pairs!

    # The pairs by supply id, as Medication::Details#replace_uses! takes them.
    def list! = pairs!.map { |supply, quantity| [ supply.id, quantity ] }

    # Names the supplies there are, so a model that translated or misspelled
    # one ("siringa" for their "Siringhe") can call again with the right name.
    def problem
      known = Supply.where(id: SupplyPurchase.accessible_by(@profile).select(:supply_id)).order(:name).limit(15).pluck(:name)
      "no supply called #{@unknown.to_sentence} has been bought yet — " +
        (known.any? ? "the user's supplies are: #{known.join(", ")} (maybe in another language). Call again with EVERY supply " \
          "the user named, each under one of those names; ask the user only if none of them fits" : "record the purchase first, or leave it out")
    end

    private

    def entries(raw)
      Array(raw).filter_map do |item|
        item = { "supply" => item } if item.is_a?(String)
        item = item.to_h.stringify_keys
        name = item.values_at(*NAME_KEYS).compact.first.to_s.squish
        next if name.empty?

        quantity = item.values_at(*QUANTITY_KEYS).compact.first.presence || 1
        [ name, quantity.to_s.tr(",", ".").to_d ]
      end
    end

    # The name this set's purchases buy it under, and the unit they keep it in.
    def bought_name(name) = @bought.keys.find { |bought| variants(bought).intersect?(variants(name)) }
    def bought_unit(name) = @bought[bought_name(name)]

    def same_unit?(kept, dose) = kept.present? && TextMatch.fold(kept.to_s.squish) == TextMatch.fold(dose.to_s.squish)

    def variants(name)
      name = TextMatch.fold(name.to_s.squish)
      [ name, name.singularize, name.pluralize ].uniq
    end

    # A bare number is a supply id, as search results show it. A name is
    # looked for among the supplies bought first, in its singular and plural
    # ("needle" is their "Needles"), then in every language the lexicon
    # knows ("needle" is their "Aghi"); a tie stays unknown.
    def find(name)
      return Supply.accessible_by(@profile).find_by(id: name) if name.match?(/\A\d+\z/)

      bought = Supply.where(id: SupplyPurchase.accessible_by(@profile).select(:supply_id))
      scopes = [ bought, Supply.where(id: Supply.accessible_by(@profile).select(:id)) ]
      spoken = [ name, name.singularize, name.pluralize ].uniq
      scopes.each do |scope|
        spoken.each do |words|
          found = NameMatch.find(scope, words)
          return found if found
        end
      end
      scopes.each do |scope|
        found = Lexicon::Matcher.find(scope, name)
        return found if found
      end
      nil
    end
  end
end
