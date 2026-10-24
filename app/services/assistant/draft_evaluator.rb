# frozen_string_literal: true

# Decides whether a draft can be saved: builds its records in memory
# (Assistant::DraftBuilder), runs their real validations, adds what the
# kind needs beyond them, and looks for likely duplicates.
#
# Writes `missing` and `warnings` onto the draft (not saved here):
#   missing:  [{ "field" => "appointment.start_time" },
#              { "field" => "transaction.amount", "problem" => "is not a number" }]
#   warnings: [{ "code" => "possible_duplicate", "existing" => { type:, id:, … } }]
#
# Warnings block saving until the user has seen them: a change set keeps
# the ones it showed, and a call that confirms acknowledges them
# (Assistant::ChangeSets::Submit).
module Assistant
  class DraftEvaluator
    # Filled in from other fields (a purchase's remaining stock starts at the
    # quantity bought): never something to ask the user. The others are
    # the records the kind itself finds or builds, reported as unresolved.
    NOT_ASKED = %i[event supply ingredient profile details collection quantity_remaining].freeze

    # At most this many possible duplicates are shown at once.
    MAX_DUPLICATES = 3

    def self.call(draft, profile:, builder: nil) = new(draft, profile:, builder:).call

    # What identifies a warning across re-evaluations: the record it points at.
    def self.warning_key(warning)
      existing = warning["existing"] || {}
      [ warning["code"], existing["type"], existing["id"] || "#{existing["event_id"]}@#{existing["date"]}" ].join(":")
    end

    def initialize(draft, profile:, builder: nil)
      @draft = draft
      @profile = profile
      @builder = builder || DraftBuilder.for(draft, profile: profile)
    end

    def call
      @draft.missing = missing
      @draft.warnings = duplicate_warnings + builder.warnings(@draft.acknowledged_warnings)
      @draft
    end

    private

    attr_reader :builder

    def missing
      problems = builder.unresolved + validation_problems + builder.missing_parts
      problems += cost_problems if builder.cost_requested?
      problems.uniq { |problem| problem["field"] }
    end

    # The built records' own errors, in the words the model used.
    def validation_problems
      kind = builder.kind
      validation_errors(builder.record).filter_map do |error|
        next if NOT_ASKED.include?(error.attribute)
        # A home meal with neither recipe nor title: the recipes are what to ask for.
        next { "field" => "meal.recipes", "problem" => error.message } if error.type == :recipes_or_title

        attribute = error.attribute.to_s.delete_prefix("details.")
        field = Assistant::Draft::FIELD_NAMES.fetch(attribute, attribute).delete_suffix("_cents")
        error.type == :blank ? { "field" => "#{kind}.#{field}" } : { "field" => "#{kind}.#{field}", "problem" => error.message }
      end
    end

    # The record's errors; for a calendar kind's first day, its series' and
    # the series details' too (Event validates its details row).
    def validation_errors(record)
      record.validate
      return record.errors.errors.dup unless record.is_a?(Occurrence)

      record.event.validate
      record.event.errors.errors + record.errors.errors
    end

    def cost_problems
      attrs = builder.cost_attributes
      problems = []
      cents = Transaction.amount_to_cents(attrs["amount"])
      problems << { "field" => "transaction.amount" } if attrs["amount"].blank?
      problems << { "field" => "transaction.amount", "problem" => "must be a number above zero" } if attrs["amount"].present? && cents.to_i <= 0
      if attrs["payment_method"].blank?
        problems << { "field" => "transaction.payment_method" }
      elsif !Transaction::Details.payment_methods.key?(attrs["payment_method"])
        problems << { "field" => "transaction.payment_method", "problem" => "must be one of #{Transaction::Details.payment_methods.keys.join(", ")}" }
      end
      problems
    end

    # Records that look like the one being drafted ("you already have a
    # visit with Moretti on Oct 2"). Server-side, so a small model can't skip it.
    def duplicate_warnings
      return [] if @draft.missing.present? && builder.section.blank?

      acknowledged = @draft.acknowledged_warnings.to_set
      builder.duplicates.uniq { |summary| summary[:id] || summary["id"] }.map { |summary| duplicate_warning(summary.deep_stringify_keys) }
        .reject { |warning| acknowledged.include?(self.class.warning_key(warning)) }
        .first(MAX_DUPLICATES)
    end

    def duplicate_warning(existing)
      warning = { "code" => "possible_duplicate", "existing" => existing }
      hint = builder.duplicate_hint(existing)
      hint ? warning.merge("hint" => hint) : warning
    end
  end
end
