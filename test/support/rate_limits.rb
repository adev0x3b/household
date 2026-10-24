# frozen_string_literal: true

module RateLimits
  # Tests cache nothing (the null store), so a rate limit never counts: for
  # the block, the controllers' store counts in memory.
  def counting_rate_limits(&)
    store = ActiveSupport::Cache::MemoryStore.new
    swapping(ApplicationController.cache_store, :increment, ->(*args, **options) { store.increment(*args, **options) }, &)
  end
end
