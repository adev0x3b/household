# frozen_string_literal: true

class Assistant::Draft
  # How the fields a model sends for one kind of draft are read: which
  # section each belongs under, the names it uses for ours, and the fields
  # that tell two drafts of the kind apart. A kind that reads its fields in
  # a way of its own is a subclass (a purchase, a payment, a lab result).
  class Shape
    attr_reader :kind

    # aliases: the names models use for a field instead of ours.
    # identity: the fields that tell two drafts of the kind apart (three
    # purchases in one message are three drafts, one per supply).
    # listed_as: the field one item of a list goes under, for a kind where
    # one create may list several things bought.
    def initialize(kind, aliases: DEFAULT_ALIASES, identity: [], listed_as: nil)
      @kind = kind
      @aliases = aliases
      @identity = identity
      @listed_as = listed_as
    end

    # The field one item of a listed create goes under ("supply"); nil for
    # a kind that is one thing per create.
    attr_reader :listed_as

    # The supply a draft of this kind buys, as [name, the unit it is counted
    # in], so a dose in the same set can use it before it is saved. Nil for
    # every kind but a supply purchase.
    def bought_supply(_fields) = nil

    # The fields filed under their sections. Models often send them flat
    # ({"provider": …, "amount": …}): cost words go under "transaction",
    # shared sections stay where they are, the rest go under the kind's
    # own section, renamed to our names.
    def normalize(fields)
      normalized = fields.to_h.deep_stringify_keys.transform_keys { |key| section_key(key) }.each_with_object({}) do |(key, value), result|
        if key == kind || SHARED_SECTIONS.include?(key)
          result[key] = value.is_a?(Hash) ? (result[key] || {}).merge(value) : value
        elsif COST_KEYS.key?(key)
          (result["transaction"] ||= {})[COST_KEYS[key]] = value
        else
          (result[kind] ||= {})[key] = value
        end
      end
      read_values!(normalized)
      return normalized unless normalized[kind].is_a?(Hash)

      file_costs!(normalized)
      normalized[kind] = rename(normalized[kind])
      normalized
    end

    # A section's fields under our names, with dates written in words read
    # ("a week ago" becomes the ISO date here rather than by the model).
    def rename(section)
      renamed = unnest(section.to_h).to_h { |key, value| [ @aliases.fetch(key, key), value ] }
      DATE_FIELDS.each do |field|
        next unless renamed[field].is_a?(String) && renamed[field].present?

        renamed[field] = Assistant::DateWords.parse(renamed[field])&.iso8601 || renamed[field]
      end
      split_count(renamed)
    end

    # The identifying fields a section has, normalized for comparison.
    def identity(section)
      @identity.filter_map { |field| [ field, section[field].to_s.strip.downcase ] if section[field].present? }.to_h
    end

    private

    # The top-level key a field is filed by: the shared sections' other
    # names, and "collection" (a therapy's name) for any kind but a
    # collection itself.
    def section_key(key) = key == "collection" ? "therapy" : SHARED_ALIASES.fetch(key, key)

    # Cost words given inside the kind's own section move to "transaction".
    def file_costs!(normalized)
      misfiled = normalized[kind].slice(*COST_KEYS.keys)
      normalized[kind] = normalized[kind].except(*COST_KEYS.keys)
      misfiled.each { |key, value| (normalized["transaction"] ||= {})[COST_KEYS[key]] ||= value }
    end

    # Values a kind keeps outside its own section, gathered into the shape
    # it reads them in.
    def read_values!(_normalized) = nil

    # A section's fields nested one level deeper than ours, flattened.
    def unnest(section) = section

    # A count written into a name, taken out of it.
    def split_count(renamed) = renamed
  end
end
