# frozen_string_literal: true

# A few series shared as one thing — what calendars call a sub-calendar: a
# therapy (its visits, doses and lab results, in Healthcare), a job hunt
# (its interviews), a renovation (its payments). Sharing a collection is a
# live grant to every series in it (Event.accessible_by), not a copy, so
# revoking it revokes access at once. Healthcare still calls its
# collections therapies on screen (i18n collections.sections.healthcare).
class Collection < ApplicationRecord
  include EditedTogether
  include Searchable
  include Shareable

  SECTIONS = %w[healthcare agenda finance pantry].freeze

  searchable_by :name

  belongs_to :profile
  has_many :events, dependent: :nullify
  has_many :supply_purchases, dependent: :nullify
  shared_through :collection_shares

  enum :status, { active: 0, paused: 1, completed: 2 }

  validates :name, presence: true
  validates :section, inclusion: { in: SECTIONS }

  scope :in_section, ->(section) { where(section: section.to_s) }
  # The person's own and those shared with them.
  scope :accessible_by, ->(profile) {
    where_id_in_any(unscoped.where(profile_id: profile.id).select(:id), CollectionShare.where(profile_id: profile.id).select(:collection_id))
  }

  # The collections a person may put a series of `section` in, by name, with
  # the one it is in already (`current_id`) even when that is of another
  # section: a visit moved to Agenda keeps its therapy. Nil when the person
  # can't reach the current one, so a series shared on its own stays where
  # it is.
  def self.choices_for(profile, section:, current_id: nil)
    reachable = accessible_by(profile)
    return if current_id && !reachable.exists?(id: current_id)

    choices = where(id: reachable.in_section(section).select(:id))
    choices = choices.or(where(id: current_id)) if current_id
    choices.order(:name)
  end

  # Shared or no longer (Shareable): every series in it appears on, or
  # leaves, the person's calendar.
  def on_shared(share, **) = redraw_calendar_of(share.profile)
  def on_unshared(share, **) = redraw_calendar_of(share.profile)

  private

  def redraw_calendar_of(profile)
    events.find_each { |event| Calendar::DayCardBroadcaster.call(event: event, extra_profiles: [ profile ]) }
  end
end
