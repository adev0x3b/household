# frozen_string_literal: true

# One day of a series, or one slot of it when the series has several a day.
# It exists as an object before anything is stored about it, and gets a row
# once something is: a status, a field changed for that day alone, a child.
class Occurrence < ApplicationRecord
  include EditedTogether
  include InheritsFromSeries
  include Costable

  belongs_to :event
  # Days are deleted through delete_with_children, which takes what hangs
  # off them in a statement per table; a stray destroy fails on a foreign
  # key rather than half-remove a day.
  has_many :lab_test_result_entries, inverse_of: :occurrence
  has_many :supply_consumptions, inverse_of: :occurrence
  has_many :meal_consumptions, inverse_of: :occurrence

  accepts_nested_attributes_for :lab_test_result_entries, allow_destroy: true,
                                                          reject_if: proc { |attrs| attrs["analyte_name"].blank? && attrs["value"].blank? }
  reads_typed_names_of :lab_test_result_entries
  reads_access_of :lab_test_result_entries

  enum :status, { pending: 0, in_progress: 1, completed: 2, cancelled: 3, skipped: 4 }

  # A dose at "08:00" is wall-clock time where the person lives, never
  # shifted between time zones.
  self.skip_time_zone_conversion_for_attributes = %i[time start_time]

  inherits :title, :notes, :location, :start_time, :duration_minutes

  delegate :profile, :recurring?, :collection, to: :event

  validates :date, presence: true
  validates :date, uniqueness: { scope: %i[event_id time] }
  validates :anchor, inclusion: { in: Events::TimesOfDay::ANCHORS.keys }, allow_nil: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :status_allowed_by_kind
  validate :skipped_reason_goes_with_skipped
  validate :completed_at_goes_with_completed
  validate :sound_for_its_kind

  # The series keeps the first day a scheduled day may have nothing saved
  # about (Event#unsaved_since): a new row may close that gap, and a row
  # that moves or goes may open one.
  after_create :advance_series_unsaved_from
  after_update :rewind_series_unsaved_from_where_it_was, if: -> { saved_change_to_date? || saved_change_to_time? }
  after_destroy :rewind_series_unsaved_from

  scope :on, ->(date) { where(date: date) }
  scope :open, -> { where.not(status: [ statuses[:completed], statuses[:cancelled], statuses[:skipped] ]) }
  scope :of_type, ->(type) { joins(:event).where(events: { type: type.to_s }) }
  scope :accessible_by, ->(profile) { where(event_id: Event.accessible_by(profile).select(:id)) }
  scope :in_order, -> { order(:date, :time, :id) }
  # The days on or after their series' Event#unsaved_since: before it,
  # every scheduled day is known to have a row.
  scope :from_unsaved_since, -> { joins(:event).where("occurrences.date >= GREATEST(events.unsaved_from, events.starts_on)") }

  class << self
    # Joins the series and, for a kind, both rows of its details, the
    # series' as `<table>_series` and the day's own as `<table>_own`, so
    # resolved_sql can read a field in SQL the way the day reads it.
    def with_series(type)
      table = type.details_class.table_name
      joins(:event)
        .joins("LEFT JOIN #{table} #{table}_series ON #{table}_series.event_id = occurrences.event_id AND #{table}_series.occurrence_id IS NULL")
        .joins("LEFT JOIN #{table} #{table}_own ON #{table}_own.occurrence_id = occurrences.id")
    end

    # SQL for a field as the day reads it: its own value, else the series'.
    # The column goes into the SQL as written, so it must be one of the
    # tables' own; anything else raises instead of reaching the query.
    def resolved_sql(column, type: nil)
      column = column.to_s
      if type && !column_names.include?(column) && type.details_class.column_names.include?(column)
        table = type.details_class.table_name
        "COALESCE(#{table}_own.#{column}, #{table}_series.#{column})"
      elsif column_names.include?(column) && Event.column_names.include?(column)
        "COALESCE(occurrences.#{column}, events.#{column})"
      elsif column_names.include?(column)
        "occurrences.#{column}"
      elsif Event.column_names.include?(column)
        "events.#{column}"
      else
        raise ArgumentError, "#{column.inspect} is no column of a day, its series#{" or #{type.details_class.table_name}" if type}"
      end
    end

    # Loads the own details row of every saved day at once, one query per
    # kind, so that `details` and the labels built from it never ask one
    # day at a time. `names_only:` loads only what naming a day reads.
    def preload_details(occurrences, names_only: false)
      days = occurrences.select { |occurrence| occurrence.persisted? && !occurrence.own_details_loaded? }
      days.group_by { |occurrence| occurrence.event.class }.each do |kind, group|
        reads = names_only ? kind.details_class.label_preloads : kind.details_class.preloads
        rows = kind.details_class.where(occurrence_id: group.map(&:id)).includes(reads).index_by(&:occurrence_id)
        group.each { |occurrence| occurrence.own_details = rows[occurrence.id] }
      end
      occurrences
    end

    # Deletes many days, records or a relation, in a statement per table
    # rather than one destroy each, so deleting a series' days costs the
    # same however many it has. What hangs off a day (its `children`) goes
    # with it, the costs about it let go of it, and its details row and the
    # requests about it are handled by the database.
    # What a kind must undo first, such as stock a dose drew, is the
    # caller's to do through the kind's hook.
    def delete_with_children(days)
      ids = days.is_a?(ActiveRecord::Relation) ? days.reselect(:id) : days.map(&:id)
      return if ids.is_a?(Array) && ids.empty?

      Event.rewind_unsaved_from(where(id: ids))
      children.each { |child| child.klass.where(child.foreign_key => ids).delete_all }
      Transaction::Details.where(about_type: name, about_id: ids).update_all(about_type: nil, about_id: nil)
      where(id: ids).delete_all
    end

    # The records that can't exist without their day: what points at it by
    # occurrence_id, not what is merely about it (Costable's cost_details).
    def children = reflect_on_all_associations(:has_many).reject { |association| association.options[:as] }
  end

  def projected? = new_record?
  def open? = !(completed? || cancelled? || skipped?)
  def event_label = own_title.presence || event.occurrence_label(self)
  def section = event.section
  def costable? = event.costable?
  def named_in_mail? = event.named_in_mail?
  def policy_class = event.class.policy_class
  def priority_rank = event.priority_rank

  # What a day is matched by within its series.
  def key = [ date, time_string ]
  def time_string = time&.strftime("%H:%M")

  def formatted_time
    I18n.l(time, format: :hour_minute) if time
  end

  def formatted_start_time
    I18n.l(start_time, format: :hour_minute) if start_time
  end

  def time_label = Events::TimesOfDay.time_label_for(time_string, anchor)
  def when_label = Events::TimesOfDay.when_label_for(time_string, anchor)

  # Days between the planned date and the day it was done: positive when
  # early, negative when late, nil until it is done.
  def days_offset
    return nil unless completed_at

    (date - completed_at.in_time_zone.to_date).to_i
  end

  # The day's own details row, nil when it has none or isn't saved yet.
  def own_details
    return @own_details if own_details_loaded?

    self.own_details = persisted? ? event.class.details_class.find_by(occurrence_id: id) : nil
  end

  # Takes the row a batch load found, pointing it back at this day and its
  # series so that reading it asks nothing more.
  def own_details=(row)
    row&.association(:occurrence)&.target = self
    row&.association(:event)&.target = event
    @own_details = row
  end

  def own_details_loaded? = instance_variable_defined?(:@own_details)

  # The kind's fields as the day reads them: its own row, else the series'.
  def details = own_details || event.details

  # When what the day reads last changed: its own row or its series', each
  # touched by its details, lists, slots and lab result values. Nil for a day of a
  # series not saved yet.
  def changed_at = [ (updated_at if persisted?), (event.updated_at if event.persisted?) ].compact.max

  # The day's own row, to write: the existing one, or a new one whose
  # readers still fall back to the series until a value is set.
  def override_details
    own_details || event.class.details_class.new(event: event, occurrence: self)
  end

  # Writes the kind's fields for this day alone, saving the day first so
  # the row has something to hang off.
  def write_details!(attributes)
    materialize!
    row = override_details
    row.assign_own(attributes)
    row.save!
    @own_details = row
  end

  def materialize!
    save! if new_record?
    self
  end

  # Takes a row built for this day as its own, saving the day first.
  def adopt_override_details!(row)
    materialize!
    row.occurrence = self
    row.event = event
    row.save!
    @own_details = row
  end

  def reload(...)
    remove_instance_variable(:@own_details) if own_details_loaded?
    super
  end

  # Marks the day done and saves it, which gives a projected day its row in
  # the same step. The kind's hook runs in the same transaction, so a dose
  # whose supplies can't be drawn isn't left marked as taken.
  def complete!(at: Time.current)
    transaction do
      self.status = :completed
      self.completed_at = at
      self.skipped_reason = nil
      save!
      event.on_occurrence_completed(self)
    end
    self
  end

  # The kind undoes what completing did, in the same transaction, so a
  # failure leaves the day as it was.
  def uncomplete!
    transaction do
      event.on_occurrence_uncompleting(self)
      update!(status: :pending, completed_at: nil)
    end
    self
  end

  # Done or not, as asked: a press that says which, read again under the
  # day's lock, so a second tap, a housemate's tap or a page that was out of
  # date changes nothing when the day already is as asked.
  def mark_completed!(completed)
    transaction do
      read_under_lock
      next if completed? == completed

      completed ? complete! : uncomplete!
    end
    self
  end

  # Any other status, with the same side effects wherever it is set:
  # leaving "completed" goes through uncomplete! first, and skipping or
  # cancelling cancels the unpaid costs attached to the day, as a cancelled
  # visit's fee shouldn't stay due; reopening restores them. Paid costs are
  # left alone. `at` is when it was done, for completed; `reason` why it
  # wasn't, for skipped.
  def change_status!(new_status, at: Time.current, reason: nil)
    new_status = new_status.to_s
    transaction do
      read_under_lock
      next complete!(at: at || Time.current) if new_status == "completed"

      uncomplete! if completed?
      self.status = new_status
      self.completed_at = nil
      self.skipped_reason = (reason.presence if new_status == "skipped")
      save!
      sync_attached_costs!(new_status)
    end
    self
  end

  private

  def inherits_from = event

  # Whether the day is done decides whether its stock goes back, so it is
  # read from the row rather than trusted from this copy: a housemate may
  # have taken the dose since this copy was read.
  def read_under_lock = persisted? ? read_status_under_lock : take_stored_row

  # Only the status is read again, with the version it is at, unlike
  # with_lock, so the series and costs already loaded stay loaded.
  def read_status_under_lock
    self.status, self.completed_at, self.lock_version = self.class.where(id: id).lock.pick(:status, :completed_at, :lock_version)
    clear_attribute_changes(%w[status completed_at lock_version])
  end

  # A projected day may have been stored by a housemate since this copy was
  # made; it then becomes that row, locked. The series' row is locked first,
  # so two first saves of one slot take turns instead of both inserting it
  # and the second failing on the slot's unique index.
  def take_stored_row
    Event.where(id: event_id).lock.pick(:id)
    stored_id = self.class.where(event_id: event_id, date: date, time: time).pick(:id) or return

    # lock! leaves a new record alone, so the row is read with reload.
    self.id = stored_id
    reload(lock: true)
  end

  # Only a day up to today can close the gap, and only one on or after it.
  def advance_series_unsaved_from
    event.advance_unsaved_from! if date <= Date.current && date >= event.unsaved_since
  end

  # The slot the day was at before it moved has no row now.
  def rewind_series_unsaved_from_where_it_was = event.rewind_unsaved_from!(date_before_last_save)
  def rewind_series_unsaved_from = event.rewind_unsaved_from!(date)

  def sync_attached_costs!(new_status)
    return unless costable?

    if %w[skipped cancelled].include?(new_status)
      costs.select(&:pending?).each { |cost| cost.change_status!("cancelled") }
    elsif new_status == "pending"
      costs.select(&:cancelled?).each { |cost| cost.change_status!("pending") }
    end
  end

  def status_allowed_by_kind
    return if event.nil? || event.class.allowed_statuses.include?(status.to_s)

    errors.add(:status, :inclusion)
  end

  def skipped_reason_goes_with_skipped
    return if skipped_reason.blank?

    errors.add(:skipped_reason, :present) unless skipped?
    errors.add(:skipped_reason, :inclusion) if event && !event.class.skip_reasons.include?(skipped_reason)
  end

  # A done day says when it was done, and only a done day does: undoing it
  # or giving it any other status lets go of the moment.
  def completed_at_goes_with_completed
    if completed?
      errors.add(:completed_at, :blank) if completed_at.nil?
    elsif completed_at
      errors.add(:completed_at, :present)
    end
  end

  # What its kind asks of one of its days (a lab result: one value per analyte).
  def sound_for_its_kind = event&.validate_occurrence(self)
end
