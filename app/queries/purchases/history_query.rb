# frozen_string_literal: true

module Purchases
  # One thing's purchases as its history page lists them, searched by a
  # single free-text term. A subclass says how its purchases are ordered and
  # which of their columns the term is matched against.
  class HistoryQuery
    PAGE_SIZE = 10

    attr_reader :filters

    def initialize(scope:, filters: {})
      @scope = scope
      @filters = { q: filters[:q].to_s.strip.presence }
    end

    # Narrowed by the ids that match rather than by `left_joins(...).distinct`:
    # Postgres refuses SELECT DISTINCT with an ORDER BY on an expression it
    # doesn't select, and a supply's purchases are ordered by one.
    def call
      return listed if @filters[:q].nil?

      listed.where(id: matching("%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q])}%").select(:id))
    end

    private

    # The purchases in the order the modal lists them.
    def listed = raise NotImplementedError

    # The purchases with `pattern`, an ILIKE pattern, in a searched column.
    def matching(pattern) = raise NotImplementedError
  end
end
