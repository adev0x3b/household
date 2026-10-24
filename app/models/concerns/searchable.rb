# frozen_string_literal: true

# `searchable_by :name` gives the model a `search(query)` scope for its index
# page's navbar search: every word of the query must appear (case- and
# accent-blind, "unita" finds "Unità") in one of the columns. A blank query
# returns everything.
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def searchable_by(*columns)
      columns = columns.map { |column| "#{table_name}.#{column}" }
      match = columns.map { |column| "unaccent(#{column}::text) ILIKE unaccent(:pattern)" }.join(" OR ")

      scope :search, ->(query) {
        query.to_s.split.reduce(all) do |scope, word|
          scope.where(match, pattern: "%#{sanitize_sql_like(word)}%")
        end
      }
    end
  end
end
