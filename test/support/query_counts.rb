# frozen_string_literal: true

# How many statements a block sends to the database, leaving out the
# schema's and what the query cache answered: what a test compares to say
# that work costs the same however many rows it touches.
module QueryCounts
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
