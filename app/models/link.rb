# frozen_string_literal: true

# Two housemates who see each other's calendars. One asks (requester), the
# other accepts (addressee); until then nothing is shared. Once accepted,
# each side's series reach the other through LinkGrant rows — what the
# other may read, write, create and delete, per kind of series, set by the
# owner of the items (so it can differ each way). One link per pair:
# `pair_key` is "lower id:higher id".
#
# Made, accepted, declined and ended only through Links::Request / Accept /
# Decline / Unlink, which notify and refresh calendars.
class Link < ApplicationRecord
  belongs_to :requester, class_name: "Profile"
  belongs_to :addressee, class_name: "Profile"
  has_many :link_grants, dependent: :delete_all
  has_many :link_approvals, dependent: :delete_all

  enum :status, { pending: 0, accepted: 1 }, validate: true

  validates :pair_key, presence: true, uniqueness: true
  # Checked when its people are given, like validates_within_household.
  validate :two_joined_people, if: -> { requester_id_changed? || addressee_id_changed? }
  validates_within_household :addressee, of: :requester

  # The pair is named when its people are given (an accept changes only the status).
  before_validation(if: -> { requester_id_changed? || addressee_id_changed? }) { self.pair_key = self.class.key_for(requester, addressee) if requester && addressee }
  # What one may do (Links::Permissions, kept per request) is read again as
  # soon as this changes, inside its transaction too, and again if that
  # transaction rolls back.
  after_save { Links::Permissions.reset! }
  after_destroy { Links::Permissions.reset! }
  after_rollback { Links::Permissions.reset! }

  scope :involving, ->(profile) { where(requester_id: profile.id).or(where(addressee_id: profile.id)) }

  def self.key_for(one, other) = [ one.id, other.id ].minmax.join(":")
  # With its two people, whom answering it notifies.
  def self.between(one, other) = includes(:requester, :addressee).find_by(pair_key: key_for(one, other))

  def partner_of(profile) = profile.id == requester_id ? addressee : requester
  def involves?(profile) = profile.id == requester_id || profile.id == addressee_id

  # What `profile` lets the other do with their items, one grant per kind,
  # in LinkGrant::TYPES' order.
  def grants_from(profile)
    given = link_grants.select { |grant| grant.grantor_id == profile.id }.index_by(&:event_type)
    LinkGrant::TYPES.map { |type| given[type] || unset_grant(profile, type) }
  end

  # The grant for one kind, saved or not yet.
  def grant_from(profile, type)
    link_grants.find_by(grantor_id: profile.id, event_type: type) || unset_grant(profile, type)
  end

  # Every kind each way, with the defaults (read on, the rest asked), made
  # when the link is accepted. A kind added to the app later has no row on
  # the links accepted before it: grants_from shows it off, and its owner's
  # first tap on the Links page saves it. The page never writes rows itself,
  # because nobody agreed to share a kind that didn't exist when they linked.
  # The missing rows go in one insert, with the columns' own defaults; a row
  # that is there already keeps its levels.
  def ensure_grants!
    return unless accepted?

    have = link_grants.pluck(:grantor_id, :event_type)
    missing = [ [ requester_id, addressee_id ], [ addressee_id, requester_id ] ].flat_map do |grantor_id, grantee_id|
      (LinkGrant::TYPES - have.filter_map { |id, type| type if id == grantor_id }).map do |type|
        { link_id: id, grantor_id: grantor_id, grantee_id: grantee_id, event_type: type }
      end
    end
    return if missing.empty?

    LinkGrant.insert_all(missing, unique_by: %i[grantor_id grantee_id event_type])
    Links::Permissions.reset!
    link_grants.reset
  end

  private

  def two_joined_people
    return unless requester && addressee

    errors.add(:addressee, :self) if requester_id == addressee_id
    errors.add(:addressee, :not_housemate) unless requester.invitation_token.nil? && addressee.invitation_token.nil?
  end

  # Built by the link's id, not through link_grants, so it stays out of
  # the association and is saved only when its owner sets it.
  def unset_grant(profile, type)
    LinkGrant.new(link_id: id, grantor: profile, grantee: partner_of(profile), event_type: type,
                  read_level: :off, write_level: :off, create_level: :off, delete_level: :off)
  end
end
