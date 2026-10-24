# frozen_string_literal: true

# What a kind's form does when it is saved: the series' shape, the day's
# fields and status, the "Remind me" rows and the kind's side effects (an
# attached cost, supplies used). Out of the controller, so the same save
# runs when a linked housemate's request is approved as when the form is
# submitted.
#
#   form = Occurrences::FormSave.for("Task").new(actor: current_profile, params: form_params)
#   authorize form.record, form.policy_query
#   form.save  # => true / false (form.record carries the errors)
#
# Three ways in: `record` given, a day of a series that exists, saved or
# not yet; `event_id`, `date` and `time` under the kind's key, the day a
# held request named (Hold), saved once its owner agrees; neither, a new
# series on `owner`'s calendar (the actor's by default).
#
# `params` is what the form sent, permitted by the controller, or what a
# held request kept: the day's fields under the kind's key (the universal
# fields, `status` with `completed_at` / `skipped_reason`, a new series'
# first day, the kind's own under `details_attributes`, a day's
# children), the series' shape under `event` (SeriesShape) and, for kinds
# with a cost section, `transaction`.
#
# A one-off always writes its series; a day of a recurring series writes
# itself unless `apply_to` says the whole series. A day keeps only what
# differs from its series (InheritsFromSeries), so it follows later edits
# to the series. The whole series takes only what the person changed on
# the day's form (Changes), never the day's own values carried along, and
# the day they edited it from follows it in those fields; the series' done
# days keep what they were done with (Event#keep_done_days_as_they_were),
# and a series with a past goes on under a new rule or new times as a new
# series (Events::Reschedule). Broadcasting happens after commit; the
# caller only renders.
module Occurrences
  class FormSave
    # The universal fields of a day (or the series), on every form.
    FIELDS = %i[title notes location start_time duration_minutes].freeze
    # What travels with a status rather than with the fields: when it was
    # done (a form's "Taken at", already in the actor's zone) and why it
    # wasn't (a skipped dose's reason).
    STATUS_DETAILS = %w[completed_at skipped_reason].freeze
    # What says which day the fields are for, and where they go, rather
    # than being a field: a form sends the day it is for (a new series'
    # first day), `apply_to`, and the versions of the day and of its series
    # it was drawn at; a held request also keeps its day's series and dose.
    VERSION_KEYS = %i[lock_version series_lock_version].freeze
    DAY_KEYS = [ :event_id, :date, :time, :anchor, :apply_to, *VERSION_KEYS ].freeze
    FORM_DAY_KEYS = [ :date, :apply_to, *VERSION_KEYS ].freeze
    COST_PARAMS = %i[amount payment_method].freeze

    def self.for(type)
      raise ArgumentError, "no form for #{type.inspect}" unless Event::TYPES.include?(type.to_s)

      const_get(type.to_s, false)
    end

    # Declared by each kind's form.
    def self.kind = raise(NotImplementedError, "#{name}.kind")
    def self.param_key = kind.model_name.param_key
    # The kind's own fields, under details_attributes.
    def self.details_fields = []
    # A day's children, under their own *_attributes key.
    def self.child_fields = []
    # Whether the form has a cost section (amount, payment method).
    def self.cost? = false

    # Everything the kind's form may send under its key, for the controller
    # to permit. The day a form is for is its address, never a field of it.
    def self.permitted_fields
      [ *FORM_DAY_KEYS, :status, *FIELDS, *STATUS_DETAILS, *child_fields, { details_attributes: details_fields } ]
    end

    attr_reader :record, :event, :actor, :series_shape, :changes, :cost_params

    def initialize(actor:, params:, record: nil, owner: nil)
      @actor = actor
      @owner = owner || actor
      params = params.to_h.with_indifferent_access
      @submitted = params.fetch(self.class.param_key, {}).with_indifferent_access
      @series_shape = SeriesShape.new(params.fetch(:event, {}), actor: actor)
      # A payment's own fields arrive under `transaction` too; only a form
      # with a cost section reads a cost there.
      @cost_params = self.class.cost? ? params.fetch(:transaction, {}).slice(*COST_PARAMS) : {}
      @record = record
      @typed = EditedTogether::TypedFields.new(params[:typed_fields], attributes, under: self.class.param_key)
      build
      @changes = Changes.new(@record, submitted: attributes, details_fields: details_scalar_fields)
    end

    def new_series? = @mode == :new_series
    def materializing? = @mode == :materialize
    def updating? = @mode == :update
    # The policy question this save asks: a new series is created, a day of
    # an existing one is edited.
    def policy_query = new_series? ? :create? : (updating? ? :update? : :edit?)

    # The day's own fields as submitted, without the keys that say which day.
    def attributes = @submitted.except(*DAY_KEYS)
    def apply_to = @submitted[:apply_to]

    # Whether the fields go to the series (a one-off, or the form said so).
    def series_scope? = new_series? || !event.recurring? || apply_to.to_s == "series"

    def save
      @errors = nil
      @errors_are_the_days = false
      @broadcasts = []
      saved = false
      ActiveRecord::Base.transaction do
        @crossed = crossed_meanwhile
        raise ActiveRecord::Rollback if @crossed

        save_series!
        series_shape.save_reminders_for(event)
        saved = save_day!
        raise ActiveRecord::Rollback unless saved

        reschedule_series!
        after_save!
        broadcast_saved
      rescue ActiveRecord::RecordInvalid => e
        @errors = e.record.errors
        @errors_are_the_days = e.record.equal?(event) || e.record.equal?(@record)
        saved = false
        raise ActiveRecord::Rollback
      end
      return refuse_crossed if @crossed
      return finish_failed unless saved

      @broadcasts.each(&:call)
      true
    end

    # The form as a request waiting for its owner's OK: what it carries,
    # what the owner is shown, whether it would save, checked when it is
    # asked rather than when approved.
    def payload = Hold.new(self).payload
    def preview = Hold.new(self).preview

    # The day's form shows the day's errors, so what is wrong with its
    # series or its kind's fields is told on the day, as a failed save does.
    def valid_for_hold?
      @crossed = crossed_meanwhile
      return refuse_crossed if @crossed

      assign_fields!(series_scope? ? series_changes : attributes.except(:status, *STATUS_DETAILS))
      invalid = [ record, event, target_details ].reject(&:valid?)
      (invalid - [ record ]).each { |part| record.errors.merge!(part.errors) }
      invalid.empty?
    end

    # The submitter's own "Remind me" rows are saved at once, even when the
    # rest waits for the owner's OK: they are the submitter's, on a series
    # that exists.
    def save_reminders!
      series_shape.save_reminders_for(event) if event.persisted?
    end

    private

    def build
      if @record
        @mode = @record.persisted? ? :update : :materialize
        @event = @record.event
        prepare_update if updating?
      elsif @submitted[:event_id].present?
        @mode = :materialize
        @event = Event.of_type(self.class.kind).includes(:event_shares, collection: :collection_shares).find(@submitted[:event_id])
        @record = @event.occurrence_on(@submitted[:date], time: @submitted[:time], anchor: @submitted[:anchor])
      else
        @mode = :new_series
        @event = self.class.kind.new(profile: @owner, starts_on: @submitted[:date])
        @record = @event.occurrence_on(@submitted[:date] || Date.current)
      end
    end

    # Before anything changes (what a taken dose used, say).
    def prepare_update; end

    # Which of the series and the day someone saved since the form was
    # drawn, read under their locks, which the save then holds until it
    # commits; nil when neither. Only a person's form says what it was
    # drawn at: a held request and the assistant don't. A day the form drew
    # with nothing stored about it has no version, so one stored meanwhile
    # is one saved meanwhile.
    def crossed_meanwhile
      return unless @submitted.key?(:series_lock_version)

      series = Event.where(id: event.id).lock.pick(:lock_version)
      day = (Occurrence.where(id: record.id).lock.pick(:lock_version) if record.persisted?)
      return record if day.to_s != @submitted[:lock_version].to_s

      event if series.to_s != @submitted[:series_lock_version].to_s
    end

    # The form again, saying who saved what it was drawn from and now
    # carrying their versions, so that saving it again keeps what was typed:
    # what was typed in it over what they saved, or everything as it was
    # sent when the form didn't say what was typed. The series and the day
    # were read as they saved them. The day's form shows the day's errors,
    # the series' included.
    def refuse_crossed
      @crossed.changed_meanwhile!(actor)
      if @crossed.equal?(record)
        event.catch_up!
      else
        record.catch_up! if record.persisted?
        record.errors.merge!(event.errors)
      end
      record.typed_fields = @typed if @typed.told?
      assign_fields!((@typed.told? ? @typed.attributes : attributes).except(:status, *STATUS_DETAILS))
      false
    end

    # Per kind, inside the transaction, after the day is saved.
    def after_save!; end

    def broadcast(&block) = @broadcasts << block

    # A series continued as a new one has days on every calendar that
    # showed it, and the old series' days from today on are gone from
    # them, so those calendars reload whole.
    def broadcast_saved
      broadcast { Calendar::DayCardBroadcaster.call(event: event) }
      broadcast { Calendar::Refresh.call(*@continuation.audience) } if @continuation
    end

    # The series: its shape, and the universal fields when they go to it. A
    # rule the form's fields can't make is the form's error.
    def save_series!
      series_shape.apply_to(event)
      raise(ActiveRecord::RecordInvalid, event.tap { _1.errors.add(:rrule, :invalid) }) unless series_shape.valid?

      changes = series_changes if series_scope?
      assign_fields!(changes) if changes
      if event.new_record? || series_scope? || event.changed? || event.details.changed_on_its_own?
        event.edited_by(actor).save!
      end
      follow_series_in!(changes) if changes
    end

    # The series' rule and times, after the day: a day done on this form is
    # then on the record before the series goes on from it. A rule with no
    # day to come is the form's error, as a rule its fields can't make is.
    def reschedule_series!
      return unless series_shape.reschedules?(event)

      result = Events::Reschedule.call(event, rrule: series_shape.rule_for(event), slots: series_shape.slots)
      raise(ActiveRecord::RecordInvalid, event.tap { _1.errors.add(:rrule, result.error) }) if result.failure?

      @continuation = result.series unless result.series.equal?(event)
    end

    # What goes to the series from this form: everything, for a new series
    # or a one-off, whose day is the series; from a day of a repeating
    # series, only what the person changed there. The form shows the day as
    # it reads, its own values included, and those stay the day's.
    def series_changes
      fields = attributes.except(:status, *STATUS_DETAILS).to_h.with_indifferent_access
      return fields if new_series? || !event.recurring?

      changes.to_h.with_indifferent_access.except(:status, *STATUS_DETAILS)
    end

    # The saved day the series was edited from follows it in what was
    # changed: its own values for those fields, and a list the form sent,
    # are cleared, including what the series' done days just kept when it
    # is one of them.
    def follow_series_in!(changed)
      return if new_series? || !event.recurring? || !record.persisted?

      plain = changed.keys.map(&:to_s) & FIELDS.map(&:to_s)
      record.update_columns(**plain.index_with { nil }, updated_at: Time.current) if plain.any?
      details = (changed[:details_attributes] || {}).to_h
      # Taken by the day first, so that clearing its lists moves on this copy
      # of the day, which the save goes on writing through.
      record.own_details = event.class.details_class.find_by(occurrence_id: record.id)
      own = record.own_details
      if own && details.any?
        fields = details.keys.map(&:to_s).reject { |key| key.end_with?("_attributes") } & own.attribute_names
        own.update_columns(**fields.index_with { nil }, updated_at: Time.current) if fields.any?
        details.keys.map(&:to_s).select { |key| key.end_with?("_attributes") }.each do |key|
          own.public_send(key.delete_suffix("_attributes")).destroy_all
        end
      end
    end

    # The day: its own fields (an override) when they go to the day, its
    # children, then a changed status through Occurrence#change_status!,
    # never straight into the column, so a dose taken then cancelled gives
    # its stock back and a cancelled visit's unpaid fee is cancelled,
    # exactly as when the assistant does it.
    def save_day!
      fields = attributes.except(:status, *STATUS_DETAILS)
      assign_fields!(fields) unless series_scope?
      if day_needs_row?
        return false unless record.edited_by(actor).save

        record.adopt_override_details!(@override_details) if @override_details&.changed_on_its_own?
      end
      apply_status!
      true
    end

    # A day gets a row once something is stored about it: it already has
    # one, its own fields or details, a child, or a status that isn't the
    # plain "pending" of a projected day.
    def day_needs_row?
      return true if record.persisted?
      return true if (record.changes.keys - %w[event_id date time anchor]).any?
      return true if @override_details&.changed_on_its_own?
      return true if child_keys.any? { |key| attributes.key?(key) }

      attributes[:status].present? && attributes[:status] != "pending"
    end

    # Where the universal fields and the kind's own go: the series, or the
    # day (its override row, built as needed). A day's children always go
    # to the day.
    def assign_fields!(fields)
      fields = fields.to_h.with_indifferent_access
      details = fields.delete(:details_attributes)
      children = fields.extract!(*child_keys)
      values = fields.transform_values { |value| value.is_a?(String) && value.empty? ? nil : value }
      if series_scope?
        event.assign_attributes(values)
        target_details.assign_attributes(details) if details.present?
      else
        record.assign_own(values)
        target_details.assign_own(details) if details.present?
      end
      record.assign_attributes(children) if children.present?
    end

    def target_details
      return event.details if series_scope?

      @override_details ||= record.override_details
    end

    def apply_status!
      status = attributes[:status].presence
      taken_at = attributes[:completed_at].presence
      reason = attributes[:skipped_reason].presence
      if status && status != record.status
        record.change_status!(status, at: taken_at, reason: reason)
      elsif record.completed? && taken_at
        record.update!(completed_at: taken_at)
      elsif record.skipped? && reason != record.skipped_reason
        record.update!(skipped_reason: reason)
      end
    end

    # After a rolled-back save the record may still say persisted? in
    # memory, since only the rows were undone: it is rebuilt so the form
    # comes back as it was sent, a new series as a new one with its rule,
    # times and collection, a day of an existing series as that day, with
    # the errors on it.
    def finish_failed
      if @errors && !updating?
        @override_details = nil
        @record = if new_series?
          self.class.kind.new(profile: @owner, starts_on: @submitted[:date]).occurrence_on(@submitted[:date] || Date.current)
        else
          event.occurrence_on(@record.date, time: @record.time_string, anchor: @record.anchor)
        end
        @event = @record.event
        series_shape.apply_to(event) if new_series?
        assign_fields!(attributes.except(:status, *STATUS_DETAILS))
      end
      import_errors
      false
    end

    # The day's own errors keep their attributes, so the form marks the
    # field. Another record's (the fee's) are added as whole sentences:
    # under their attributes they would read as the day's.
    def import_errors
      return if @errors.nil? || @errors.equal?(@record.errors)

      if @errors_are_the_days
        @record.errors.merge!(@errors)
      else
        @errors.each { |error| @record.errors.add(:base, error.full_message) }
      end
    end

    # A cost section's payment, attached to the day (a visit's fee, a meal out).
    def sync_cost!(**fields)
      return if cost_params[:amount].blank?

      change = Transactions::SetCost.call(record, date: record.date,
                                                  amount: cost_params[:amount], payment_method: cost_params[:payment_method], **fields)
      broadcast { Calendar::DayCardBroadcaster.call(event: change.cost.event, dates: Array(change.moved_from)) }
    end

    # The keys a day's children arrive under.
    def child_keys = self.class.child_fields.flat_map { |field| field.is_a?(Hash) ? field.keys : field }
    def details_scalar_fields = self.class.details_fields.reject { |field| field.is_a?(Hash) }
  end
end
