# frozen_string_literal: true

# Who may change a series as a whole, apart from any one of its days: the
# assistant asks before its undo restores one. A day is OccurrencePolicy's,
# and sharing the series is SharePolicy's.
class EventPolicy < ApplicationPolicy
  def update?
    owner? || shared? || link_allows_writing?
  end

  private

  def link_allows_writing?
    ::Links::Permissions.for(user).allows?(record.profile_id, record.type, :write)
  end
end
