# frozen_string_literal: true

class Assistant::Draft
  # A collection's own section is "collection", so the word is never a
  # therapy's name to file elsewhere.
  class CollectionShape < Shape
    private

    def section_key(key) = SHARED_ALIASES.fetch(key, key)
  end
end
