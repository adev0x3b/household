# frozen_string_literal: true

module Assistant
  module Operations
    # Something new of any kind a Draft can hold. What each kind builds,
    # needs and saves is its Assistant::DraftBuilder, so a create stays the
    # same for every kind. A calendar kind's create is a new series and its
    # first day, saved together.
    class Create < Base
      attr_reader :draft, :builder

      # A later mention of the same new record (the date of a lab result
      # named earlier) belongs to it: what identifies each draft doesn't
      # disagree (Draft.same_item?).
      def self.same_spec?(a, b) = Draft.same_item?(identity(a), identity(b))

      def self.identity(spec)
        type = spec["type"]
        Draft.identity(type, Draft.normalize_payload(type, spec["fields"]).fetch(type, {}))
      end
      private_class_method :identity

      def check
        fail!("#{type} can't be created; types: #{Draft::KINDS.join(", ")}") unless Draft::KINDS.include?(type)

        @draft = Draft.new(kind: type, profile: profile, chat: context.chat, acknowledged_warnings: context.acknowledged)
        @draft.merge_payload(fields)
        @builder = DraftBuilder.for(@draft, profile: profile, catalog: context.lab_catalog, pantry_catalog: context.pantry_catalog,
                                            supplies_bought: context.supplies_bought)
        ignored = @builder.prune_unknown!
        @notes << "not understood, not saved: #{ignored.join(", ")}" if ignored.any?
        DraftEvaluator.call(@draft, profile: profile, builder: @builder)
        @missing = @draft.missing.map { |problem| [ problem["field"], problem["problem"] ].compact.join(" ") }
        screening = @builder.screen(@draft.warnings, context.acknowledged)
        @warnings = screening.warnings
        fail!(screening.refusal) if screening.refusal

        @notes.concat(@builder.notes)
        note_who_sees
      end

      def seen_by = @seen_by ||= @builder ? resource.readers(@builder.record).excluding(profile) : []

      def waits_for_purchase? = @builder.present? && @builder.waits_for_purchase?

      # A dose whose uses name a supply this set buys is created after the
      # purchases.
      def phase = waits_for_purchase? ? :using_purchases : :creating

      # Units the user gave for this lab result's analytes (for a range in
      # the same change set that doesn't name one).
      def lab_units = @builder ? @builder.lab_units : {}

      def apply!(applier)
        # The user already accepted the warnings before the set could
        # apply, and DraftCommitter refuses a draft that still has any.
        @draft.warnings = []
        @builder.use_purchases!
        result = DraftCommitter.call(@draft, profile: profile, builder: @builder)
        applier.defer(result.broadcasts)
        applier.remember(spec["as"], result.records.first)
        applier.saved(result.records.map { |record| summarize(record) })
        result.records.map { |record| entry("created", record) }
      end

      def label = @builder&.record ? @builder.label : super
    end
  end
end
