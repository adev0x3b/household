# frozen_string_literal: true

# What a linked housemate (grantee) may do with one kind of the grantor's
# items: read (off / on), write, create and delete (off / on / ask — "ask"
# holds the action as a LinkApproval until the grantor OKs it). Without
# read nothing else is possible, so turning read off turns the rest off.
#
# Rows exist only while their Link is accepted, so a row means "linked":
# Event.accessible_by and Links::Permissions read them without the link.
class LinkGrant < ApplicationRecord
  # Every kind of series (the Event hierarchy), granted one by one.
  TYPES = Event::TYPES
  ACTIONS = %w[read write create delete].freeze
  LEVELS = { off: 0, on: 1, ask: 2 }.freeze

  belongs_to :link
  belongs_to :grantor, class_name: "Profile"
  belongs_to :grantee, class_name: "Profile"

  enum :read_level, LEVELS.slice(:off, :on), prefix: :read, validate: true
  enum :write_level, LEVELS, prefix: :write, validate: true
  enum :create_level, LEVELS, prefix: :create, validate: true
  enum :delete_level, LEVELS, prefix: :delete, validate: true

  validates :event_type, inclusion: { in: TYPES }
  validates :event_type, uniqueness: { scope: %i[grantor_id grantee_id] }

  before_validation :nothing_without_read
  # What one may do (Links::Permissions, kept per request) is read again as
  # soon as this changes, inside its transaction too, and again if that
  # transaction rolls back.
  after_save { Links::Permissions.reset! }
  after_destroy { Links::Permissions.reset! }
  after_rollback { Links::Permissions.reset! }

  scope :readable, -> { where(read_level: read_levels[:on]) }

  # In the order the page offers them: no, ask me, yes.
  def self.levels_for(action) = action.to_s == "read" ? %w[off on] : %w[off ask on]

  # The kind of series it grants, one of Event.types.
  def kind = event_type.constantize

  # :on / :ask / :off
  def level(action)
    raise ArgumentError, "unknown action #{action.inspect}" unless ACTIONS.include?(action.to_s)

    public_send(:"#{action}_level").to_sym
  end

  private

  def nothing_without_read
    return unless read_off?

    self.write_level = :off
    self.create_level = :off
    self.delete_level = :off
  end
end
