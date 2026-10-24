# frozen_string_literal: true

module Details
  # A kind's own fields, in the kind's own table: one row for the series and,
  # only where a day differs from it, one row for that day. The series' row
  # must be complete; a day's row holds only what differs.
  class Base < ApplicationRecord
    self.abstract_class = true

    include InheritsFromSeries

    belongs_to :event
    belongs_to :occurrence, optional: true

    scope :series, -> { where(occurrence_id: nil) }
    scope :overrides, -> { where.not(occurrence_id: nil) }

    validate :occurrence_belongs_to_event
    before_update :keep_done_days_as_they_were, if: :series?

    # A row changed is what it describes changed, so that "changed since
    # you asked" (undo, a linked housemate's request) sees an edit to the
    # kind's fields alone.
    after_save :touch_described, if: :saved_changes?
    after_destroy :touch_described, unless: :destroyed_by_association

    class << self
      # What reading a row needs loaded with it, for the batch loads.
      def preloads = []

      # What naming a day reads beyond the row, the lighter load for lists
      # of days by name.
      def label_preloads = []

      # The kind's fields a done day keeps as it was done when the series
      # changes later.
      def recorded = []

      # The row's lists, such as a dose's planned supplies.
      def lists = []

      def series_requires(*names)
        names.each { |name| validates name, presence: true, if: :series? }
      end
    end

    def series? = occurrence_id.nil? && occurrence.nil?

    def touch_described = (occurrence || event).mark_changed!

    # The series' row; itself, for the series' row.
    def series_row = series? ? self : event.details

    # Copies the fields and the lists onto another series' row, for a
    # series continued as a new one.
    def copy_to(row)
      row.assign_attributes(attributes.except("id", "event_id", "occurrence_id", "created_at", "updated_at"))
      self.class.lists.each do |name|
        foreign_key = association(name).reflection.foreign_key
        public_send(name).each do |item|
          row.public_send(name).build(item.attributes.except("id", foreign_key, "created_at", "updated_at"))
        end
      end
    end

    # Whether the row has something of its own to save: a field, or a
    # change to one of its lists, not just the keys it was built with.
    def changed_on_its_own?
      return true if (changes.keys - %w[event_id occurrence_id]).any?

      self.class.lists.any? do |name|
        association(name).target.any? { |item| item.new_record? || item.changed? || item.marked_for_destruction? }
      end
    end

    # Before an item of the series' list changes, each done day of a
    # repeating series without a list of its own takes the list as it is
    # stored now, so that editing the series never rewrites what was done.
    # A day with its own list is left alone. Done once per transaction: a
    # form saving three supplies is one change, not three. Written in bulk
    # without touching anything, as a copy of what a done day already reads
    # changes nothing it shows.
    def keep_done_days_list!(name)
      return unless series? && persisted? && event.keeps_history?
      return if kept_in_this_transaction?(name)

      list = association(name).scope.to_a
      days = event.occurrences.completed.pluck(:id)
      return if list.empty? || days.empty?

      own = self.class.where(event_id: event_id, occurrence_id: days).includes(name).index_by(&:occurrence_id)
      rows = own.values.reject { |row| row.public_send(name).any? }.map(&:id)
      missing = days - own.keys
      rows += self.class.insert_all!(missing.map { |occurrence_id| { event_id: event_id, occurrence_id: occurrence_id } }, returning: %w[id]).rows.flatten if missing.any?
      return if rows.empty?

      foreign_key = association(name).reflection.foreign_key
      copies = list.map { |item| item.attributes.except("id", foreign_key, "created_at", "updated_at") }
      association(name).klass.insert_all!(rows.flat_map { |row_id| copies.map { |copy| copy.merge(foreign_key => row_id) } })
    end

    private

    def inherits_from = series_row
    def follows_series? = !series?

    def kept_in_this_transaction?(name)
      transaction = self.class.connection.current_transaction
      return false unless transaction.open?

      @kept_lists = [ transaction, Set.new ] unless @kept_lists&.first.equal?(transaction)
      !@kept_lists.last.add?(name)
    end

    # Before the series' row changes a recorded field, every done day of a
    # repeating series that read it from here takes the old value as its
    # own, on its row or on a new one, so that editing the series changes
    # what is still to come and never what happened. Only a value can be
    # kept: a field the series left empty reads what it is given later.
    def keep_done_days_as_they_were
      return unless event.keeps_history?

      names = self.class.recorded.map(&:to_s).select { |name| will_save_change_to_attribute?(name) && !attribute_in_database(name).nil? }
      return if names.empty?

      done = event.occurrences.completed
      old = names.to_h { |name| [ name, self.class.type_for_attribute(name).serialize(attribute_in_database(name)) ] }
      own = self.class.where(event_id: event_id, occurrence_id: done.select(:id))
      old.each { |name, value| own.where(name => nil).update_all(name => value, updated_at: Time.current) }

      missing = done.where.not(id: self.class.overrides.where(event_id: event_id).select(:occurrence_id)).pluck(:id)
      self.class.insert_all!(missing.map { |occurrence_id| { event_id: event_id, occurrence_id: occurrence_id, **old } }) if missing.any?
    end

    def occurrence_belongs_to_event
      return if occurrence.nil? || event.nil? || occurrence.event_id == event.id || occurrence.event.equal?(event)

      errors.add(:occurrence, :invalid)
    end
  end
end
