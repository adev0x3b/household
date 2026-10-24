# frozen_string_literal: true

# The people who run a home together, and the boundary of everything they
# keep here. A profile lives in one household; its records are its own, it
# can share them with housemates only (WithinHousehold), and the unit
# vocabulary is the household's. Nothing is visible from another household.
#
# Invite only: the app's admin creates a household by inviting its first
# member (Households::Create), who becomes its owner, and members invite the
# others (Households::Invite). The owner and the admin can remove people
# (ProfilePolicy, Profiles::Destroy).
#
# What a household may do in a day — ask the assistant
# (Assistant::MessageAllowance), look books up (Books::LookupAllowance) —
# how much it may keep in Files (Uploads::Quota), how many people it may
# hold and how many each member may invite are the installation's limits
# (Platform), the same for every household of a copy. The demo household (`bin/rails demo:seed`,
# Demo::Seeder) is one like any other, filled with six months of made-up
# activity; the demo installation's limits are config/deploy.demo.yml's.
class Household < ApplicationRecord
  # The first member's invitation, typed with the household's name (Households::Create).
  attr_accessor :first_member_email, :first_member_first_name

  has_many :profiles, dependent: :restrict_with_error
  # Who runs it: the first member (Households::Create), who can remove the others.
  belongs_to :owner, class_name: "Profile", optional: true
  has_many :units, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.to_s.squish }
  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }

  before_validation { self.slug = name.to_s.parameterize if slug.blank? }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/, allow_blank: true }
  # What it counts money in (ISO 4217): a payment's when none is said, an
  # empty report's. Amounts in other currencies are never added to it.
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }

  # What this household's assistant use cost over a period (Assistant::Usage::Row).
  def assistant_usage(period = Time.current.all_month) = Assistant::Usage.for(self, period)

  def members = profiles.joined

  def invitations = profiles.invitation_pending

  # Everyone counts against the installation's household size, people
  # invited and not yet joined included. A size lowered below a household's
  # count removes nobody: it is full until people leave.
  def full?
    left = places_left
    !left.nil? && left.zero?
  end

  # How many more people fit; nil: no limit.
  def places_left
    size = Platform.household_size or return

    [ size - profiles.count, 0 ].max
  end

  # How many more people `profile` can invite here; nil: no limit. Its own
  # household: what's left of the installation's invitations per member (an
  # invitation cancelled gives one back) — none where the installation has
  # invitations off (Platform.invitations?), unless they run the app.
  # Someone else's, for the admin who runs the app: as many as there are
  # places.
  def invites_left_for(profile)
    return places_left unless profile.household_id == id
    return 0 unless profile.admin? || Platform.invitations?

    [ own_invites_left(profile), places_left ].compact.min
  end

  private

  def own_invites_left(profile)
    allowed = Platform.invitations_per_member or return

    [ allowed - profiles.where(invited_by: profile).count, 0 ].max
  end
end
