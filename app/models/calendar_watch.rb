# frozen_string_literal: true

# A calendar month someone has open: one row per CalendarChannel
# subscription ("profile_<id>:<YYYY>-<MM>"), so every process — the web
# server holding the connection, the job worker pushing a day card — knows
# which months are worth rendering. The channel refreshes its
# row while the page is open and deletes it when it closes; a row a crashed
# process left behind stops counting after STALE_AFTER and is swept later.
class CalendarWatch < ApplicationRecord
  REFRESH_EVERY = 1.minute
  STALE_AFTER = 3.minutes
  ROOM = /\Aprofile_(\d+):(\d{4}-\d{2})\z/

  belongs_to :profile

  # The months `profile_id` has open, as "YYYY-MM".
  def self.months_for(profile_id) = months_by_profile([ profile_id ]).fetch(profile_id, [])

  # { profile_id => [ "YYYY-MM", … ] } for those with any month open: one
  # query for a whole audience.
  def self.months_by_profile(profile_ids)
    where(profile_id: profile_ids, seen_at: STALE_AFTER.ago..).distinct.pluck(:profile_id, :year_month)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  # `room` is open in `subscription` (now, or still).
  def self.watch!(room, subscription)
    profile_id, year_month = room.to_s.match(ROOM)&.captures
    return unless profile_id

    upsert({ profile_id: profile_id, year_month: year_month, subscription: subscription, seen_at: Time.current }, unique_by: :subscription)
  end

  def self.unwatch!(subscription) = where(subscription: subscription).delete_all

  # Rows nothing refreshes any more (a process that stopped without closing them).
  def self.sweep! = where(seen_at: ...1.hour.ago).delete_all
end
