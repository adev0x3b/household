# frozen_string_literal: true

# A series on someone's calendar: what every kind of series shares. The
# kinds are its subclasses, and the hierarchy is the registry: everything
# that enumerates the kinds reads Event.types, except the assistant, which
# keeps its own list of what it reads.
class Event < ApplicationRecord
  include EditedTogether
  include Shareable

  TYPES = %w[Task Appointment Medication Meal LabTestResult Transaction].freeze
  DEFAULT_PRIORITY_RANK = 1
  # What a done day keeps as it was done when its series changes later;
  # each kind adds its own fields and lists.
  RECORDED_FIELDS = %w[title location start_time duration_minutes].freeze
  # What a series' continuation carries over.
  CONTINUED_FIELDS = %w[title notes location start_time duration_minutes collection_id].freeze

  belongs_to :profile
  belongs_to :collection, optional: true
  # A series is removed through Events::Purge, which deletes it with its
  # days in a statement per table. Its days, its details and its reminders
  # say no `dependent:`, so a stray destroy fails on a foreign key rather
  # than half-remove a series.
  has_many :occurrences
  has_many :event_reminders
  # Slots are replaced as a set (assign_slots), which deletes the ones left out.
  has_many :event_slots, -> { order(:position) }, dependent: :destroy, inverse_of: :event
  has_many :event_exclusions, dependent: :destroy, inverse_of: :event
  shared_through :event_shares
  # The expenses whose series' row says they pay for this series.
  has_many :cost_details, as: :about, class_name: "Transaction::Details", dependent: :nullify

  # A visit at "11:00" is wall-clock time where the person lives, never
  # shifted between time zones.
  self.skip_time_zone_conversion_for_attributes = [ :start_time ]

  validates :starts_on, presence: true
  validates :type, inclusion: { in: TYPES }
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates_accessible :collection, by: :profile
  validate :rrule_parses

  before_update :keep_done_days_as_they_were
  after_update :recheck_unsaved_from, if: -> { saved_change_to_rrule? || saved_change_to_starts_on? }

  scope :of_type, ->(type) { where(type: type.to_s) }
  scope :starting_on, ->(date) { where(starts_on: date) }
  scope :between, ->(from, to) { where(starts_on: from..to) }
  # Series that may have a day in the range: a one-off inside it, or a
  # repeating series that started by its end.
  scope :visible_in, ->(from, to) {
    where(rrule: nil).where(starts_on: from..to).or(where.not(rrule: nil).where(starts_on: ..to))
  }
  scope :with_saved_in, ->(range) { where(id: Occurrence.where(date: range).select(:event_id)) }
  # Series nothing was ever saved about. Asked per series, so Postgres
  # answers it from the index on the days' event_id instead of reading
  # every household's days, as `NOT IN (SELECT event_id …)` would.
  scope :without_saved_days, -> { where(Occurrence.where(Occurrence.arel_table[:event_id].eq(arel_table[:id])).arel.exists.not) }

  class << self
    def types = TYPES.map(&:constantize)

    # Declared by each kind: the table of its own fields. The series' row
    # is built on first touch and validated and saved with the series, so
    # a series never exists without it.
    def has_details(class_name)
      has_one :details, -> { where(occurrence_id: nil) }, class_name: class_name, inverse_of: :event, autosave: true
      accepts_nested_attributes_for :details
      define_method(:details) { association(:details).reader || association(:details).build }
      before_validation { details }
    end

    # The section of the household it belongs to; nil when decided per
    # series, as an appointment's kind decides it.
    def section = nil
    # Where a new series of it starts, before its form says otherwise.
    def starting_section = section
    def policy_class = OccurrencePolicy
    # The category a cost of one of its days is filed under.
    def fee_category = :miscellaneous
    def allowed_statuses = %w[pending completed cancelled skipped]
    # Why one of its days wasn't done.
    def skip_reasons = []
    def details_class = const_get(:Details, false)
    def route_key = model_name.singular_route_key
    def default_title = I18n.t("#{model_name.route_key}.default_title")
    def costable? = true
    # Whether a reminder mail may name its series. Mail is read on lock
    # screens and kept on servers the household doesn't choose, so a kind
    # whose names could tell of someone's health (a medication, a lab test,
    # an appointment that may be a doctor's) is called by its kind alone,
    # and a kind is named only once it says it may be.
    def named_in_mail? = false
    def section_scope(section) = section.to_s == self.section.to_s ? all : none

    # What its days' calendar cards read beyond their series and details,
    # loaded for a batch of days at once.
    def preload_for_cards(_days); end

    # The attribute type of a field of its days or its details, for a
    # preview of what a linked housemate asks to change.
    def attribute_type_for(name)
      name = name.to_s
      return Occurrence.type_for_attribute(name) if Occurrence.column_names.include?(name)
      return details_class.type_for_attribute(name) if details_class.column_names.include?(name)

      type_for_attribute(name)
    end

    def human_attribute_name_for(name)
      name = name.to_s
      return details_class.human_attribute_name(name) if details_class.column_names.include?(name) && !Occurrence.column_names.include?(name)

      Occurrence.human_attribute_name(name)
    end

    # Series owned by, shared with, or readable by `profile`: a share on
    # the series, a share on its collection, a link grant on its kind from
    # its owner, or, for a payment between housemates, being its
    # counterparty. Each way in is a lookup of ids of its own, so a series
    # comes out once however many ways it is reached.
    def accessible_by(profile)
      series = Event.unscoped
      where_id_in_any(
        series.where(profile_id: profile.id).select(:id),
        EventShare.where(profile_id: profile.id).select(:event_id),
        series.where(collection_id: CollectionShare.where(profile_id: profile.id).select(:collection_id)).select(:id),
        series.where(
          "(events.profile_id, events.type) IN (SELECT grantor_id, event_type FROM link_grants WHERE grantee_id = :id AND read_level = :on)",
          id: profile.id, on: LinkGrant.read_levels[:on]
        ).select(:id),
        Transaction::Details.where(occurrence_id: nil, counterparty_profile_id: profile.id).select(:event_id)
      )
    end

    # Series of one section: the kinds that belong to it whole, plus the
    # series of the kinds that decide per series.
    def in_section(section)
      whole = types.select { |type| type.section.to_s == section.to_s }.map(&:name)
      types.select { |type| type.section.nil? }.reduce(where(type: whole)) do |scope, type|
        scope.or(where(id: type.section_scope(section).select(:id)))
      end
    end

    # Loads the saved days of many series in a range in one query, with
    # what reading them needs, so that a month, a report or a day card
    # costs the same however many series it shows.
    def preload_occurrences(events, from, to)
      events = preload_series(events)
      return events if events.empty?

      saved = Occurrence.where(event_id: events.map(&:id), date: from..to).group_by(&:event_id)
      events.each { |event| event.cache_occurrences(saved.fetch(event.id, []), from, to) }
      Occurrence.preload_details(saved.values.flatten)
      events
    end

    # The same for each series' first day alone, the day a collection's
    # page opens a series on.
    def preload_first_occurrences(events)
      events = preload_series(events)
      return events if events.empty?

      saved = Occurrence.joins(:event).where(event_id: events.map(&:id)).where("occurrences.date = events.starts_on").group_by(&:event_id)
      events.each { |event| event.cache_occurrences(saved.fetch(event.id, []), event.starts_on, event.starts_on) }
      Occurrence.preload_details(saved.values.flatten)
      events
    end

    # Loads what reading a series' days needs of the series: its slots,
    # its exclusions and its details, a kind at a time since each kind's
    # details read something else. `names_only:` loads only what naming
    # the days reads.
    def preload_series(events, names_only: false)
      events = events.to_a
      return events if events.empty?

      ActiveRecord::Associations::Preloader.new(records: events, associations: %i[event_slots event_exclusions]).call
      events.group_by(&:class).each do |klass, group|
        reads = names_only ? klass.details_class.label_preloads : klass.details_class.preloads
        ActiveRecord::Associations::Preloader.new(records: group, associations: { details: reads }).call
      end
      events
    end

    # The audience of many series at once, in a few queries: their owners
    # and sharees, their collections' sharees, the linked readers of each
    # owner's kind, and the kinds' extra readers.
    def audience_of(events)
      events = events.to_a
      ActiveRecord::Associations::Preloader.new(records: events, associations: [ :profile, { event_shares: :profile },
                                                                                 { collection: :shared_profiles } ]).call
      events.group_by(&:class).each { |kind, group| kind.preload_audience(group) }
      grants = LinkGrant.readable.where(grantor_id: events.map(&:profile_id).uniq, event_type: events.map(&:type).uniq).pluck(:grantor_id, :event_type, :grantee_id)
      readers = Profile.where(id: grants.map(&:last).uniq).index_by(&:id)
      events.flat_map do |event|
        linked = grants.filter_map { |grantor_id, type, grantee_id| readers[grantee_id] if grantor_id == event.profile_id && type == event.type }
        [ event.profile, *event.event_shares.map(&:profile), *event.collection&.shared_profiles, *linked, *event.extra_readers ]
      end.compact.uniq
    end

    # What its extra readers read, loaded for many of its series.
    def preload_audience(_events); end

    # Event#rewind_unsaved_from! for the series of many days about to be
    # deleted, in one statement: each goes back to the first of its days.
    def rewind_unsaved_from(days)
      firsts = days.group(:event_id).select("occurrences.event_id, MIN(occurrences.date) AS first_date")
      joins("JOIN (#{firsts.to_sql}) firsts ON firsts.event_id = events.id")
        .where("events.unsaved_from > firsts.first_date")
        .update_all("unsaved_from = firsts.first_date")
    end
  end

  def section = self.class.section
  def fee_category = self.class.fee_category
  def costable? = self.class.costable?
  def named_in_mail? = self.class.named_in_mail?
  def event_label = title.presence || self.class.default_title
  def shared_name = event_label
  # The label of one of its days; a kind may word a day by its own details.
  def occurrence_label(_occurrence) = event_label

  # What a reminder mail calls one of its days: "your task “Water the
  # plants”", or "your medication" for a kind a mail doesn't name
  # (Event.named_in_mail?).
  def reminder_mail_thing(occurrence)
    key = "#{self.class.model_name.route_key}.reminder_mail.thing"
    named_in_mail? ? I18n.t(key, name: occurrence.event_label) : I18n.t(key)
  end

  # The title of a cost attached to one of its days, and who it was paid
  # to unless the cost says: a visit's provider, the place a meal was eaten.
  def cost_title(occurrence) = occurrence.event_label
  def cost_counterpart(_occurrence) = nil
  def priority_rank = DEFAULT_PRIORITY_RANK

  # The i18n key of the notice that one of its days was marked done or not
  # done, as `viewer` reads it; a kind that words it by who reads it says so.
  def completion_notice_key(completed, _occurrence, _viewer)
    "#{self.class.model_name.route_key}.notices.#{completed ? "completed" : "uncompleted"}"
  end

  # What a kind asks of one of its days beyond what every day must satisfy,
  # said as errors on the day.
  def validate_occurrence(_occurrence); end
  # What happens to one of its days, overridden by the kinds.
  def on_occurrence_completed(_occurrence); end
  def on_occurrence_uncompleting(_occurrence); end
  # Its days about to be deleted, saved or not, several at once when a
  # series goes whole: what the kind gives back of what they did.
  def on_occurrences_destroying(_days); end

  # Shared or no longer: its days appear on, or leave, the person's calendar.
  def on_shared(share, **) = Calendar::DayCardBroadcaster.call(event: self, extra_profiles: [ share.profile ])
  def on_unshared(share, **) = Calendar::DayCardBroadcaster.call(event: self, extra_profiles: [ share.profile ])

  # When one of its days is due, as [[hour, minute], timed]: the slot's
  # time when the day has one, else the morning.
  def due_clock(occurrence)
    return [ Events::TimesOfDay.clock(occurrence.time_string), true ] if occurrence.time_string

    [ Events::TimesOfDay::MORNING, false ]
  end

  # Everyone who sees it on their calendar: its owner, whoever it is
  # shared with, alone or through its collection, linked readers, and
  # whoever else the kind lets in.
  def audience
    ([ profile ] + shared_profiles.to_a + collection_readers + link_readers.to_a + extra_readers).compact.uniq
  end

  def collection_readers = collection ? collection.shared_profiles.to_a : []

  def extra_readers = []

  # The day of another series a day of this one is about, when its kind can
  # be about one (a payment for a visit); a calendar shows such a day inside
  # that one's card. A day of most kinds is about nothing but itself.
  def about_day(_occurrence) = nil

  # The linked housemates its owner lets read this kind of series.
  def link_readers
    Profile.where(id: LinkGrant.readable.where(grantor_id: profile_id, event_type: type).select(:grantee_id))
  end

  def recurring? = rrule.present?

  # Whether some of its days are behind, before today. What happened on
  # them is a record, so a change to how it repeats goes on from today
  # rather than from its start (Events::Reschedule).
  def past_days? = starts_on < Date.current

  # The series going on as a new one from `starts_on`, which is what a
  # change "from now on" does to a series with a past: the old one ends,
  # this one takes over with the same body, collection, times of the day
  # and details, lists included. Its rule is the caller's to set; a kind
  # adds what continuing means for it.
  def continuation(starts_on:)
    copy = self.class.new(attributes.slice(*CONTINUED_FIELDS).merge("profile_id" => profile_id, "starts_on" => starts_on))
    copy.assign_slots(event_slots.map { |slot| slot.anchor || slot.time_string })
    details.copy_to(copy.details)
    copy
  end

  # One person's "remind me" rows on the series, soonest before first.
  def reminders_of(profile) = event_reminders.for_profile(profile).order(:offset_minutes)

  # Whoever saw this series sees its continuation, and their reminders follow.
  def hand_over_audience_to!(continuation)
    event_shares.each { |share| continuation.event_shares.create!(profile_id: share.profile_id) }
    event_reminders.each do |reminder|
      continuation.event_reminders.create!(profile_id: reminder.profile_id, offset_minutes: reminder.offset_minutes, by_email: reminder.by_email)
    end
  end

  # Whether the series repeats, or did before this save: its done days are
  # then history, kept as they were when it changes.
  def keeps_history? = rrule.present? || rrule_in_database.present?

  def rrule=(value)
    @schedule = nil
    super(value.presence)
  end

  def starts_on=(value)
    @schedule = nil
    super
  end

  def schedule
    @schedule ||= Events::Schedule.new(starts_on, rrule)
  end

  def reload(...)
    @schedule = nil
    @occurrence_cache = nil
    super
  end

  # The day's slots as [ "HH:MM", anchor or nil ] in clock order; one
  # untimed slot when the series has none.
  def slots
    event_slots.any? ? event_slots.map { |slot| [ slot.time_string, slot.anchor ] } : [ [ nil, nil ] ]
  end

  # Sets the day's slots from entries such as "08:00" or "CV", replacing
  # them only when they differ: a form sends them with every save, and a
  # slot written counts as a change to the series, so "changed since you
  # asked" (undo, a linked housemate's request) must see only a real one.
  # A saved series writes them at once, and new times may have no row on
  # days already passed.
  def assign_slots(entries)
    return unless slots_differ_from?(entries)

    self.event_slots = EventSlot.rows_for(entries)
    recheck_unsaved_from if persisted?
  end

  # Whether entries such as "08:00" or "CV" are other times than the series' own.
  def slots_differ_from?(entries)
    EventSlot.rows_for(entries).map { [ _1.time_string, _1.anchor ] } != event_slots.map { [ _1.time_string, _1.anchor ] }
  end

  def timed? = event_slots.any?
  def first_slot = slots.first

  # The anchor a slot came from, nil for a clock time or a time off the
  # series' slots.
  def anchor_for(time)
    slots.find { |slot_time, _| slot_time == time }&.last
  end

  # Every scheduled date between two dates, minus the days deleted.
  def occurrence_dates_between(from, to)
    dates = if recurring?
      schedule.dates_between(from, to)
    else
      (from..to).cover?(starts_on) ? [ starts_on ] : []
    end
    dates - excluded_days
  end

  # Every day between two dates, by date then time: the schedule's dates
  # times the day's slots, minus the single slots deleted, each as its
  # saved row or an unsaved day; plus the saved days that match no slot or
  # date, such as a day moved or a dose at an extra time, so that nothing
  # recorded disappears.
  def occurrences_between(from, to)
    saved = saved_occurrences_between(from, to)
    seen = []

    scheduled = scheduled_slots_between(from, to).map do |day, time, anchor|
      key = [ day, time ]
      seen << key
      saved[key] || Occurrence.new(event: self, date: day, time: time, anchor: anchor)
    end
    off_schedule = saved.reject { |key, _| seen.include?(key) }.values

    (scheduled + off_schedule).sort_by { |occurrence| [ occurrence.date, occurrence.time_string.to_s, occurrence.id.to_i ] }
  end

  # The scheduled days between two dates that nothing was saved about,
  # given the [date, "HH:MM"] keys of the days that were. Reading years of
  # a series this way loads none of its rows, which is what listing what
  # needs attention however old relies on.
  def unsaved_days_between(from, to, saved_keys)
    scheduled_slots_between(from, to).filter_map do |day, time, anchor|
      Occurrence.new(event: self, date: day, time: time, anchor: anchor) unless saved_keys.include?([ day, time ])
    end
  end

  # The day at `date`, and at `time` for a timed series: its saved row,
  # else a new one. A time off the series' slots is allowed, for an extra
  # dose.
  def occurrence_on(date, time: nil, anchor: nil)
    date = date.to_date
    time = Events::TimesOfDay.hhmm(time) if time.present?
    saved_occurrence(date, time) || Occurrence.new(event: self, date: date, time: time, anchor: anchor || anchor_for(time))
  end

  # The day to act on: the one at `time` when given; else the first slot
  # of the day still to do, or the last when all are done.
  def occurrence_for(date, time: nil, anchor: nil)
    return occurrence_on(date, time: time, anchor: anchor) if time.present?

    candidates = occurrences_between(date.to_date, date.to_date)
    return occurrence_on(date) if candidates.empty?

    candidates.find(&:pending?) || candidates.last
  end

  # The day the series starts with, at its first slot for a timed series.
  def first_occurrence
    time, anchor = first_slot
    occurrence_on(starts_on, time: time, anchor: anchor)
  end

  def materialized_on?(date) = occurrences.exists?(date: date)
  def excluded_on?(date) = excluded_days.include?(date.to_date)

  # The first day a scheduled day of it may have nothing saved about:
  # every one before has a row, whatever its status. Reading which days
  # were never saved starts here rather than at the series' first day, so
  # it costs the same however long the series has run. The stored day is
  # kept low rather than exact: a writer that can't tell moves it back,
  # and a series nothing was saved about yet has none and reads from its
  # start.
  def unsaved_since = [ unsaved_from, starts_on ].compact.max

  # Moves the stored day to the first scheduled slot up to today without a
  # row, or to tomorrow when every one has one. The series' row is locked
  # first, so two saves at once take turns and the second reads the
  # first's day. The lock is the one an update takes (FOR NO KEY UPDATE),
  # which a day inserted beforehand in the same transaction doesn't
  # conflict with, so two such saves wait for each other rather than
  # deadlock. The day is written without moving updated_at, which "changed
  # since you asked" (undo, a linked housemate's request) reads as a change,
  # or the version, which a form open on the series does.
  def advance_unsaved_from!(from: nil)
    stored = self.class.where(id: id).lock("FOR NO KEY UPDATE").pick(:unsaved_from)
    start = [ from || stored, starts_on ].compact.max
    today = Date.current
    first = start > today ? start : first_unsaved_date(start, today) || today.next_day
    update_columns_keeping_version(unsaved_from: first) unless first == stored
  end

  # A scheduled day from `date` on may have lost its row: the stored day
  # goes back to it if it was past it, without reading anything.
  def rewind_unsaved_from!(date)
    self.class.where(id: id).where(unsaved_from: date.next_day..).update_all_keeping_version(unsaved_from: date)
  end

  # Removes a day from the series, or one slot of it, so it isn't
  # projected again; the saved row, if any, is the caller's to delete.
  def skip!(date, time: nil) = skip_all!([ [ date, time ] ])

  # Many days or slots at once, as [[date, time], …], in one insert; one
  # already removed stays as it is.
  def skip_all!(days)
    rows = days.map { |date, time| { event_id: id, date: date.to_date, time: (Events::TimesOfDay.hhmm(time) if time.present?) } }.uniq
    EventExclusion.insert_all(rows, unique_by: %i[event_id date time]) if rows.any?
    event_exclusions.reset
  end

  def unskip!(date, time: nil)
    time = Events::TimesOfDay.hhmm(time) if time.present?
    event_exclusions.where(date: date.to_date).select { |exclusion| exclusion.time_string == time }.each(&:destroy!)
    event_exclusions.reset
    rewind_unsaved_from!(date.to_date)
  end

  # Keeps the saved days of a range, loaded by Event.preload_occurrences,
  # so that walking the range needs no query.
  def cache_occurrences(saved, from, to)
    @occurrence_cache = { range: from.to_date..to.to_date, by_key: saved.each { |occurrence| occurrence.event = self }.index_by(&:key) }
  end

  private

  def saved_occurrences_between(from, to)
    if @occurrence_cache && @occurrence_cache[:range].cover?(from.to_date) && @occurrence_cache[:range].cover?(to.to_date)
      @occurrence_cache[:by_key].select { |(date, _), _| (from.to_date..to.to_date).cover?(date) }
    else
      occurrences.where(date: from..to).each { |occurrence| occurrence.event = self }.index_by(&:key)
    end
  end

  def saved_occurrence(date, time)
    if @occurrence_cache&.dig(:range)&.cover?(date)
      @occurrence_cache[:by_key][[ date, time ]]
    else
      occurrences.find_by(date: date, time: time)&.tap { |occurrence| occurrence.event = self }
    end
  end

  # Every scheduled [date, "HH:MM" or nil, anchor] between two dates: the
  # rule's dates times the day's slots, minus the days and single slots
  # deleted.
  def scheduled_slots_between(from, to)
    excluded = excluded_slots
    times = slots
    occurrence_dates_between(from, to).flat_map do |day|
      times.filter_map { |time, anchor| [ day, time, anchor ] unless excluded.include?([ day, time ]) }
    end
  end

  # The date of the first scheduled slot between two dates that has no row.
  def first_unsaved_date(from, to)
    saved = occurrences.where(date: from..to).pluck(:date, :time).to_set { |date, time| [ date, time&.strftime("%H:%M") ] }
    scheduled_slots_between(from, to).find { |day, time, _| !saved.include?([ day, time ]) }&.first
  end

  # A new rule, start or set of times may schedule slots on days already
  # passed that have no row, or take away the ones that had: the stored
  # day is found again from the series' start.
  def recheck_unsaved_from = advance_unsaved_from!(from: starts_on)

  def excluded_days
    event_exclusions.select { |exclusion| exclusion.time.nil? }.map(&:date)
  end

  def excluded_slots
    event_exclusions.reject { |exclusion| exclusion.time.nil? }.map { |exclusion| [ exclusion.date, exclusion.time_string ] }
  end

  def rrule_parses
    return if rrule.blank?

    Events::RecurrenceRule.parse(rrule)
  rescue ArgumentError => e
    errors.add(:rrule, :invalid, message: e.message)
  end

  # A done day is a record of what was done. Before a repeating series'
  # own fields change, every completed day that read them from the series
  # takes the old value as its own, one statement per field, so that
  # editing the series changes what is still to come and never what
  # happened. A one-off's day is the series itself, so editing one edits
  # the other. Only a value can be kept: a field the series left empty
  # reads what it is given later.
  def keep_done_days_as_they_were
    return unless keeps_history?

    RECORDED_FIELDS.each do |name|
      old = attribute_in_database(name)
      next if old.nil? || !will_save_change_to_attribute?(name)

      occurrences.completed.where(name => nil).update_all_keeping_version(name => old, updated_at: Time.current)
    end
  end
end
