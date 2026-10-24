# frozen_string_literal: true

# Who may do what with a day of a series (the record is an Occurrence, its
# series `record.event`): the owner; whoever it is shared with, directly or
# through its collection; and a linked housemate, as far as the owner's
# LinkGrant on that kind of series goes — on, off, or "ask" (the change is
# then held as a LinkApproval, see #needs_approval?).
module EventAuthorizable
  extend ActiveSupport::Concern

  ACTION_FOR = {
    show?: :read, edit?: :write, update?: :write, change_status?: :write,
    destroy?: :delete, create?: :create
  }.freeze

  def show?
    owner_or_shared? || link_allows?(:read)
  end

  # Whether `query` on this record must wait for the owner's OK.
  def needs_approval?(query)
    action = ACTION_FOR.fetch(query.to_sym)
    return false if owner?
    return false if action == :write && shared? && shared_writable?

    link_permissions.asks?(event.profile_id, event.type, action)
  end

  private

  def event = record.event
  def owning_record = event

  # The series itself, or its collection.
  def shared? = super || event.collection&.shared_with?(user) || false

  def owner_or_shared?
    owner? || shared?
  end

  def shared_writable? = true

  def writable?
    owner? || (shared? && shared_writable?) || link_allows?(:write)
  end

  def deletable?
    owner? || link_allows?(:delete)
  end

  # A new series goes on one's own calendar, or on a linked housemate's who
  # lets one add (or ask to add) that kind.
  def creatable?
    owner? || link_permissions.allows?(event.profile_id, event.type, :create)
  end

  def link_allows?(action)
    return false if event.new_record?

    link_permissions.allows?(event.profile_id, event.type, action)
  end

  def link_permissions = ::Links::Permissions.for(user)
end
