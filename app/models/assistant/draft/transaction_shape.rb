# frozen_string_literal: true

class Assistant::Draft
  # A payment's own section is its cost: its cost words stay in it, under
  # our names, with nothing to move.
  class TransactionShape < Shape
    def normalize(fields)
      normalized = fields.to_h.deep_stringify_keys.transform_keys { |key| section_key(key) }.each_with_object({}) do |(key, value), result|
        if key == kind || SHARED_SECTIONS.include?(key)
          result[key] = value.is_a?(Hash) ? (result[key] || {}).merge(value) : value
        else
          (result[kind] ||= {})[key] = value
        end
      end
      normalized[kind] = rename(normalized[kind]) if normalized[kind].is_a?(Hash)
      normalized
    end
  end
end
