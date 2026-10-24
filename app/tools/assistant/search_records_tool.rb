# frozen_string_literal: true

module Assistant
  class SearchRecordsTool < Tool
    description "Searches the user's records. With date_from and date_to it also returns upcoming occurrences of " \
                "repeating series (id null, use event_id + date). Always search before creating something."
    parameter :type, description: Resources.keys.to_sentence(two_words_connector: " or ", last_word_connector: " or ", locale: false)
    parameter :query, description: "Words to look for, e.g. a name or provider", required: false
    parameter :date_from, description: "ISO date, inclusive", required: false
    parameter :date_to, description: "ISO date, inclusive", required: false
    parameter :status, description: "pending, completed, cancelled or skipped", required: false
    parameter :collection_id, type: :integer, description: "Only records of this therapy (its collection_id)", required: false

    # Models still send a collection's id as therapy_id.
    def execute(type:, query: nil, date_from: nil, date_to: nil, status: nil, collection_id: nil, therapy_id: nil)
      from = date(date_from, "date_from")
      to = date(date_to, "date_to")
      from ||= to if to
      to ||= from if from

      results = resource(type).search(profile, query:, date_from: from, date_to: to, status:, collection_id: collection_id || therapy_id)
      { count: results.size, results: results }
    end
  end
end
