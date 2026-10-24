# frozen_string_literal: true

# Something a linked housemate (requester) asked to do with the owner's
# item where the owner's LinkGrant says "ask": create one, change one,
# mark one done or not, delete a day or a series. Held here until the owner
# approves (Links::Approvals::Decide runs it as the owner) or declines.
# A request about a day names its date and, for a series taken several
# times a day, the time of its dose.
#
#   payload  form: the form's params (only what changed, see
#            Occurrences::FormSave#payload); assistant: { "spec" => op spec }
#   preview  [{ attribute, from, to }] — what the owner is shown
class LinkApproval < ApplicationRecord
  EXPIRES_AFTER = 30.days

  belongs_to :link
  belongs_to :requester, class_name: "Profile"
  belongs_to :owner, class_name: "Profile"
  belongs_to :event, optional: true

  enum :action_kind, { create: 0, update: 1, complete: 2, uncomplete: 3, destroy: 4 }, prefix: :to, validate: true
  enum :source, { form: 0, assistant: 1 }, prefix: :from, validate: true
  enum :status, { pending: 0, approved: 1, declined: 2, failed: 3, withdrawn: 4, cancelled: 5 }, validate: true
  # Why an approved request couldn't be done: what it was about is gone, it
  # changed so the request no longer holds, or the owner may no longer do it.
  enum :failure, { gone: 0, changed: 1, not_allowed: 2 }, prefix: true, validate: { allow_nil: true }

  # The reason in words, written in the approver's language. Read by the
  # version still serving during a deploy; the column goes after it.
  self.ignored_columns += %w[error]

  validates :event_type, inclusion: { in: LinkGrant::TYPES }
  validates :title, presence: true
  validates :scope, inclusion: { in: Occurrences::Destroy::SCOPES }, allow_nil: true

  scope :live, -> { pending.where(created_at: EXPIRES_AFTER.ago..) }
  scope :involving, ->(profile) { where(requester_id: profile.id).or(where(owner_id: profile.id)) }
  scope :recent, -> { order(created_at: :desc) }

  def live? = pending? && created_at >= EXPIRES_AFTER.ago

  # A value of a kind's `attribute` as the owner reads it in a preview: a
  # time of day without its date, a day without its time (enums are worded
  # by the page). `kind` is the Event subclass (or its name).
  def self.shown(kind, attribute, value)
    return if value.nil?

    kind = kind.constantize if kind.is_a?(String)
    type = kind.attribute_type_for(attribute.to_s)
    cast = type.cast(value)
    case type.type
    when :time then cast&.strftime("%H:%M")
    when :date then cast&.iso8601
    else value.to_s
    end
  end

  # What is asked, in i18n terms: create / update / complete / uncomplete /
  # destroy, and for a deletion whether it is the whole series.
  def verb = to_destroy? && scope == "series" ? "destroy_series" : action_kind

  # The owner changed the day, or its series, after it was asked for.
  def changed_since?
    return false unless base_updated_at

    current = record&.changed_at || event&.updated_at
    current.present? && current > base_updated_at + 1.second
  end

  def time_string = time&.strftime("%H:%M")
  def when_label = Events::TimesOfDay.when_label_for(time_string, nil)

  # The saved day it is about, if there is one.
  def record
    return unless event

    @record ||= (occurrence_id && Occurrence.find_by(id: occurrence_id, event_id: event.id)) ||
                (date && event.occurrence_on(date, time: time_string).then { |occurrence| occurrence if occurrence.persisted? })
  end

  # The kind of series it is about.
  def kind = event_type.constantize
end
