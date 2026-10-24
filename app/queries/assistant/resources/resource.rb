# frozen_string_literal: true

module Assistant
  module Resources
    # One kind of record the assistant works with. A subclass says what it
    # is: its key (the type the model names), its model, how its records are
    # scoped to a profile, the columns a search reads, the fields a change
    # may write, and what a summary says about each record. Everything that
    # is the same for every kind is here: finding records by id under the
    # profile's own access, the search, and the shape of a summary.
    #
    # A calendar kind is a CalendarResource: its records are days of a
    # series, saved or not yet.
    class Resource
      include Words

      def key = raise(NotImplementedError, "#{self.class} must say its key")
      def model = raise(NotImplementedError, "#{self.class} must say its model")
      def search_columns = raise(NotImplementedError, "#{self.class} must say what a search reads")
      def writable = raise(NotImplementedError, "#{self.class} must say what a change may write")

      # Every record of this kind the profile may see.
      def scope(_profile) = raise(NotImplementedError, "#{self.class} must say how its records are scoped")

      # What a summary says about each of `records`, in their order: one
      # hash per record, without the facts every summary carries (type, id).
      def summaries(_records, _profile) = raise(NotImplementedError, "#{self.class} must say what its summaries read")

      # A writable field's allowed values, by field.
      def enums = {}

      # The column a date filter reads and the newest-first order follows;
      # nil for a kind with no date of its own.
      def date_column = nil

      # Records that match through another table: a lab result by the
      # analytes in it. `matching` turns column names into the SQL condition
      # for the words being searched, exact or close.
      def search_also(_matching) = nil

      # The records the user is using now, most recent first, for a kind
      # where "the list" means the one in use; nil for the others.
      def in_use(_profile) = nil

      # What people call the kind itself, so words that only name it ("la
      # lista della spesa") mean the one in use rather than a record called that.
      def kind_words = []

      def type = nil
      def eventable? = false
      def completable? = false
      def in_use? = false
      def kind_word?(word) = kind_words.include?(word)

      # Whether a day of it can hold several doses, told apart by their time
      # ("… at 20:00", "… at dinner").
      def doses? = false

      # What else a record of it holds, which an update can add to or take
      # from: a meal's recipes, a lab result's values, a list's items.
      def recipes? = false
      def lab_values? = false
      def list_items? = false

      # Whether two of its records can be merged into one (an analyte
      # written two ways).
      def mergeable? = false

      # Whether a cost (a fee, a price) can hang off one of its records.
      def costable? = model.include?(Costable)

      # Everyone who sees one of its records, saved or not yet: its owner,
      # and whoever it is shared with for a kind that can be shared.
      def readers(record) = model.include?(Shareable) ? record.people_with_access : [ record.profile ]

      def accessible(profile) = scope(profile)

      def find_accessible(profile, id) = where_accessible(profile, id).find(id)

      # Its records dated within `days`, newest first; every record of a
      # kind with no date of its own.
      def dated_within(profile, days)
        return accessible(profile) unless date_column

        newest_first(accessible(profile).where(date_column => days))
      end

      # Records by id with what their policies read.
      def where_accessible(profile, ids) = accessible(profile).where(id: ids)

      def summarize(record, profile:) = summarize_all([ record ], profile: profile).first

      # One summary per record, in their order, read in as few queries as
      # the kind allows: a page of results is many records, and the model
      # waits for all of them.
      def summarize_all(records, profile:)
        records = records.to_a
        return [] if records.empty?

        read_for_summaries(records)
        records.zip(summaries(records, profile)).map { |record, own| facts(record, profile).merge(own).compact }
      end

      # Words match accent-blind; when nothing matches them exactly, close
      # spellings do ("estradio1"), closest first (Assistant::TextMatch).
      # A page for the model is MAX_RESULTS; an operation over everything
      # that matched asks for one more, to know when there is more.
      def search(profile, query: nil, date_from: nil, date_to: nil, status: nil, collection_id: nil, limit: MAX_RESULTS)
        limit = [ limit.to_i, 1 ].max
        words = TextMatch.significant(TextMatch.fold(query).scan(/[[:alnum:]]{2,}/).uniq)
        # Words asked for and none to match ("x", "?"): nothing, rather than everything.
        return [] if query.to_s.strip.present? && words.empty?

        relation = accessible(profile)
        relation = relation.where(status: status) if status.present? && model.respond_to?(:statuses)
        relation = filter_collection(relation, collection_id) if collection_id.present?
        relation = relation.where(date_column => date_range(date_from, date_to)) if date_column && (date_from || date_to)
        matched = newest_first(match_words(relation, words))

        found = summarize_all(matched.limit(limit).to_a, profile: profile)
        found += unsaved_matches(profile, words, date_from, date_to, status, collection_id, limit)
        return found.sort_by { |r| [ r[:date].to_s, r[:time].to_s ] }.first(limit) if found.any? || !similar(words)

        summarize_all(close_matches(relation, words).limit(limit).to_a, profile: profile)
      end

      private

      # What every summary carries.
      def facts(record, _profile) = { type: key, id: record.id }

      # Loads what the summaries of `records` read, before they are built.
      def read_for_summaries(records)
        Costable.preload_cost(records) if costable?
      end

      # Days a search finds that have no row to match: a calendar kind's
      # projected days and untouched series. Nothing, for the other kinds.
      def unsaved_matches(_profile, _words, _date_from, _date_to, _status, _collection_id, _limit) = []

      # From one date, up to another, or between the two.
      def date_range(from, to)
        return (from..) if to.nil?
        return (..to) if from.nil?

        from..to
      end

      # A column as the record reads it; "table.column" as written.
      def columns
        search_columns.map { |column| column.to_s.include?(".") ? column.to_s : "#{model.table_name}.#{column}" }
      end

      def newest_first(relation)
        date_column ? relation.reorder(date_column => :desc, id: :desc) : relation.reorder(:id)
      end

      def match_words(relation, words)
        return relation if words.empty?

        matched = relation.where(TextMatch.contains(columns, words))
        also = search_also(->(cols) { TextMatch.contains(cols, words) })
        also ? matched.or(relation.where(id: also)) : matched
      end

      def similar(words) = words.any? && TextMatch.similar(columns, words)

      # Closest first. A record found only through search_also (a lab
      # report by an analyte's name) scores by its own columns, so ranks last.
      def close_matches(relation, words)
        matched = relation.where(similar(words))
        also = search_also(->(cols) { TextMatch.similar(cols, words) })
        matched = matched.or(relation.where(id: also)) if also
        matched.reorder(Arel.sql("#{TextMatch.score(columns, words)} DESC"), id: :desc)
      end

      # Records of one collection (a therapy): those that belong to it, or
      # the collection itself.
      def filter_collection(relation, collection_id)
        return relation.where(collection_id: collection_id) if model.column_names.include?("collection_id")

        relation.where(id: collection_id)
      end

      # Loads associations onto records already in memory.
      def load(records, *associations)
        ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
        records
      end
    end
  end
end
