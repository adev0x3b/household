# frozen_string_literal: true

module Assistant
  module Operations
    # One operation of a change set. A subclass answers:
    #   check            resolves and validates without writing, and fills
    #                    missing, problems, warnings, candidates and notes
    #   apply!(applier)  writes it and returns its undo entries
    #   label            what it is about, in the user's words
    #                    ("Lab results on 16 September 2026")
    #   phase            when it applies within its set (PHASES)
    class Base
      include UndoEntry

      # The order operations of one set apply in, whatever order the model
      # gave them: a record exists before it is changed, a dose's supplies
      # are bought before the dose uses them, a report is whole before its
      # ranges are set, everything is in place before it is marked done or
      # shared, and deletions come last.
      PHASES = %i[creating using_purchases changing setting_ranges finishing deleting].freeze

      # The statuses an operation can be in once checked, from the one that
      # ends the call to the one that applies now. Only :ready and :confirm
      # can be applied; :confirm waits for the user's button first.
      STATUSES = %i[invalid ambiguous missing confirm ready].freeze

      IDENTIFYING = %w[title counterpart provider name supply analyte date occurrence_date time].freeze

      GONE = "something this change was about went, or changed hands, since the user was shown it: " \
             "look it up again and make the call again"

      attr_reader :spec, :index, :context, :missing, :problems, :warnings, :candidates, :notes

      # Whether two specs of this op and type are about the same thing, so
      # that a later call merges into the earlier one: the same record, or
      # the same records asked for.
      def self.same_spec?(a, b) = names(a) == names(b)

      def self.names(spec) = spec["ref"].to_s.downcase.squish.presence || spec["fields"].slice("ids", "all", "query").to_s
      private_class_method :names

      def initialize(spec, index:, context:)
        @spec = spec
        @index = index
        @context = context
      end

      def op = spec["op"]
      def type = spec["type"]
      def fields = spec["fields"].to_h
      def ref = spec["ref"]
      def intent = spec["intent"]
      def profile = context.profile
      def resource = Resources.fetch(type)

      def phase = raise(NotImplementedError, "#{self.class} must say when it applies")
      def apply_order = PHASES.index(phase)

      def compile
        @missing = []
        @problems = []
        @warnings = []
        @candidates = []
        @notes = []
        check
        self
      rescue Failure, ArgumentError => e
        @problems << e.message
        self
      rescue ActiveRecord::RecordInvalid => e
        @problems << e.record.errors.full_messages.to_sentence
        self
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        @problems << "not found, or not the user's to change"
        self
      end

      def status
        return :invalid if problems.any?
        return :ambiguous if candidates.any?
        return :missing if missing.any?
        return :confirm if needs_confirmation?

        :ready
      end

      def ready? = status == :ready || status == :confirm
      # A dose's supplies (uses) name one this set is still buying: it can't
      # be saved before that purchase is.
      def waits_for_purchase? = false
      def needs_confirmation? = risky? || seen_by.any? || unacknowledged_warnings.any?
      def risky? = false

      # Whoever besides the user sees what this writes: a payment's
      # counterparty, a shared list's readers, a linked housemate whose item
      # it is. The user's words would reach them, so the change waits for
      # the button as a share does, and the card says who. Nobody, for an
      # operation that writes no words of the user's.
      def seen_by = []
      def warning_keys = warnings.map { |w| DraftEvaluator.warning_key(w) }
      def unacknowledged_warnings = warnings.reject { |w| context.acknowledged.include?(DraftEvaluator.warning_key(w)) }

      # What the user sees on the card, localized ("Ask Sam: …" when it
      # waits for a linked housemate's OK).
      def summary
        text = I18n.t("assistant.operations.#{op}", thing: label)
        held? ? I18n.t("assistant.operations.ask_owner", name: approval_owner.display_name, change: text) : text
      end

      # What the model sees.
      def to_result
        { n: index, intent: intent, op: op, type: type, status: status.to_s, summary: summary,
          needs_approval_from: approval_owner&.display_name, seen_by: seen_by.map(&:display_name).presence,
          missing: missing.presence, problems: problems.presence, candidates: candidates.presence,
          warnings: warnings.presence, notes: notes.presence }.compact
      end

      # A linked housemate's item whose owner must OK this change (their
      # LinkGrant says "ask"): the applier holds it as a LinkApproval
      # (Links::Approvals::Hold.from_operation) instead of writing it.
      attr_reader :approval_owner, :approval_record

      def held? = approval_owner.present?

      # What the owner is asked to allow (a LinkApproval's action_kind).
      def approval_kind = "update"

      # The same op, about that one day by id (or its series, date and
      # time while it has no row), to run as its owner once approved.
      def pinned_spec
        record = approval_record
        ref = record.persisted? ? record.id : "event_id #{record.event_id} on #{record.date.iso8601}#{" at #{record.time_string}" if record.time}"
        spec.except("intent", "pinned").merge("ref" => ref, "fields" => fields.except("all", "ids", "query", "date_from", "date_to", "event_id", "date"))
      end

      # The records it was checked against (none for a create). When the set
      # waits for the user's button, they are kept on the spec as pins
      # (ChangeSets::Submit), so the press applies to the records the card
      # listed and to no others: never searched for again, and refused when
      # one of them went or changed hands in between (Resolver#pinned).
      def checked_records = []

      def pinned_for_confirmation
        pins = checked_records.map { |record| pin(record) }
        pins.any? ? spec.merge("pinned" => pins) : spec
      end

      def pinned? = spec["pinned"].present?

      # The changes shown to the owner, as [{ attribute, from, to }]; only an
      # update has any.
      def preview_rows = []

      def label = I18n.t("assistant.types.#{type}", default: type.to_s.humanize)

      private

      def fail!(message) = raise(Failure, message)

      # Said once the record is known, so the model can tell the user why
      # the card waits.
      def note_who_sees
        names = seen_by.map(&:display_name)
        @notes << "#{names.to_sentence(locale: :en)} will see this: it waits for the user's Apply button." if names.any?
      end

      # A saved record by id; a day of a series with no row yet by its series,
      # date and time.
      def pin(record)
        return { "id" => record.id } if record.persisted?

        { "event_id" => record.event_id, "date" => record.date.iso8601, "time" => record.time_string }.compact
      end

      # The records the user was shown, exactly as they are now.
      def pinned_records
        records = context.resolver.pinned(type, spec["pinned"])
        fail!(GONE) unless records.all?

        records
      end

      # After authorizing: does any of these need its owner's OK? Then this
      # op is held, about one record only, never mixed with the user's own.
      def ask_owner_for(records, query)
        asking = records.select do |record|
          record.respond_to?(:event) && record.event && Pundit.policy!(profile, record).try(:needs_approval?, query)
        end
        return if asking.empty?

        owner = asking.first.event.profile
        if records.size > 1
          fail!("#{owner.display_name} has to OK changes to their #{type.humanize(capitalize: false).pluralize}: " \
                "ask about one at a time, apart from the user's own")
        end
        @approval_owner = owner
        @approval_record = asking.first
        @notes << "this is #{owner.display_name}'s: it will be sent to them to OK, not saved now"
      end

      # Whether a bare series ref (no day) means the series' next day, for a
      # change to what it does from now on (Resolver#resolve's upcoming).
      def upcoming_ref? = false

      # The record this op is about: its ref, or, when the model named it in
      # fields instead, those fields (title, counterpart, date…), or
      # event_id and date. Nil when several could be meant: they are the
      # candidates then.
      def resolve!(from_fields: true)
        return pinned_records.first if pinned?

        if from_fields && ref.blank? && fields["event_id"].present? && (on = DateWords.parse(fields["date"] || fields["occurrence_date"]))
          event = Event.accessible_by(profile).of_type(resource.type).find(fields["event_id"])
          time = Events::TimesOfDay.code_for(fields["time"]) if event.timed? && fields["time"].present?
          return event.occurrence_for(on, time: time && Events::TimesOfDay.hhmm(time))
        end

        words = ref.presence
        words ||= fields.slice(*IDENTIFYING).values.select { |v| v.is_a?(String) || v.is_a?(Numeric) }.join(" ").presence if from_fields
        resolution = context.resolver.resolve(type, words, upcoming: upcoming_ref?)
        fail!("#{op} can't refer to #{ref} created in the same change — put these details in its create") if resolution.handle
        @candidates = resolution.candidates
        fail!(resolution.problem) if resolution.problem && resolution.candidates.empty?
        @notes << "assumed the most recent #{type}" if resolution.assumed
        resolution.record
      end

      def summarize(record) = Resources.for_record(record).summarize(record, profile: profile)
    end
  end
end
