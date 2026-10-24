# frozen_string_literal: true

class Profile < ApplicationRecord
  # Invite only: nobody signs up. A profile is created by an invitation
  # (Households::Invite) and becomes usable when it is accepted. A password
  # is reset by a link from the household page (Profiles::PasswordLink),
  # never by email; how long, how many tries, how idle:
  # config/initializers/devise.rb.
  devise :invitable, :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable,
         :lockable, :timeoutable

  belongs_to :household

  # Removing someone is Profiles::Destroy: everything they kept, in foreign
  # key order, and what others kept about them unlinked. Nothing here is
  # destroyed with the profile, so `destroy` — right only for an invitation
  # not accepted yet, which owns nothing — fails on a foreign key instead of
  # half-removing a person through other models' callbacks.
  has_many :events
  has_many :event_shares
  has_many :shared_events, through: :event_shares, source: :event
  has_many :collections
  has_many :collection_shares
  has_many :shared_collections, through: :collection_shares, source: :collection
  has_many :analytes
  has_many :ingredients
  has_many :supplies
  has_many :recipes
  has_many :recipe_shares
  has_many :shared_recipes, through: :recipe_shares, source: :recipe
  has_many :grocery_lists
  has_many :grocery_list_shares
  has_many :shared_grocery_lists, through: :grocery_list_shares, source: :grocery_list
  has_many :books
  has_many :book_shares
  has_many :shared_books, through: :book_shares, source: :book
  has_one :bookshelf
  has_many :bookshelf_shares
  has_many :shared_bookshelves, through: :bookshelf_shares, source: :bookshelf
  has_many :uploads
  has_many :upload_shares
  has_many :shared_uploads, through: :upload_shares, source: :upload

  has_many :conversation_participants
  has_many :conversations, through: :conversation_participants
  has_many :messages, foreign_key: :sender_id, inverse_of: :sender
  has_many :message_reactions

  has_many :notifications
  has_many :push_subscriptions
  has_many :event_reminders
  has_many :sent_links, class_name: "Link", foreign_key: :requester_id, inverse_of: :requester
  has_many :received_links, class_name: "Link", foreign_key: :addressee_id, inverse_of: :addressee

  attr_writer :login

  normalizes :email, with: ->(email) { email.strip.downcase }

  # Who has an account: never invited (seeds), or accepted. The others are
  # invitations waiting for an answer: an email, no username, nothing to share with.
  scope :joined, -> { where(invitation_token: nil) }
  scope :invitation_pending, -> { where.not(invitation_token: nil) }
  # How people are listed: by first name, by username where there is none.
  scope :by_name, -> { order(:first_name, :username) }
  scope :oldest_invitation_first, -> { order(:invitation_created_at, :id) }
  # Whoever goes by one of these usernames, in any case: compared in lower
  # case, as the unique index compares them, so the index answers.
  scope :with_username, ->(usernames) {
    where("lower(username) IN (?)", Array(usernames).map { _1.to_s.strip.downcase })
  }

  # Someone invited picks a username when accepting: required from then on,
  # unique always (an invitation has none yet, and that's no clash).
  validates :username, presence: true, unless: :invitation_pending?
  validates :username, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :prohibit_email_as_username
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }, allow_nil: true
  validate :time_zone_known

  enum :gender, { male: 0, female: 1, non_binary: 2 }
  enum :role, { user: 0, admin: 1 }

  def login
    @login || self.username || self.email
  end

  # A token for the link that sets a new password (Profiles::PasswordLink),
  # readable only now: the database keeps its digest, and an earlier link
  # stops working.
  def password_link_token! = set_reset_password_token

  # Their clock (the browser's, saved by time_zone_controller.js), for
  # "3 hours before"; the app's until a browser has said.
  def zone = (time_zone.present? && ActiveSupport::TimeZone[time_zone]) || Time.zone

  # As this person sees it: their language and their clock, so "today", a
  # time and a date are theirs. Every request runs in its
  # viewer's (ApplicationController#in_viewer_zone); what is made for
  # someone else — a broadcast, a push, a notification — runs in theirs.
  def as_viewer(&) = I18n.with_locale(locale.presence || I18n.default_locale) { Time.use_zone(zone, &) }

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup

    if (login = conditions.delete(:login))
      people = where(conditions.to_h)
      people.with_username(login).or(people.where("lower(email) = ?", login.strip.downcase)).first
    elsif conditions.has_key?(:username) || conditions.has_key?(:email)
      where(conditions.to_h).first
    end
  end

  # The other people of the household: who a record can be shared with, who
  # can be the other side of a transfer.
  def housemates = Profile.joined.where(household_id: household_id).where.not(id: id)

  # The housemates one is linked with (accepted links), who see one's
  # calendar as each other's grants allow.
  def link_partners
    Profile.where(id: Link.accepted.where(requester_id: id).select(:addressee_id))
      .or(Profile.where(id: Link.accepted.where(addressee_id: id).select(:requester_id)))
  end

  def invitation_pending? = invitation_token.present?

  # A fresh link to accept this invitation, the earlier one no longer
  # working: the token comes back readable this once, as the database keeps
  # its digest. Never mailed (skip_invitation): the inviter hands
  # it over. A renewed invitation stays its first inviter's, since it still
  # counts as theirs.
  def issue_invitation!(inviter)
    self.skip_invitation = true
    self.invitation_token = nil
    invite!(invited_by || inviter)
    raw_invitation_token
  end

  # Their shelf as one thing to share (Bookshelf), made the first time it is asked for.
  def bookshelf! = bookshelf || create_bookshelf!

  # What to call them: their first name, else their username, else (not
  # joined yet) their email. Where several people are shown together,
  # Profiles::DisplayNames tells two of the same name apart.
  def display_name = first_name.presence || username.presence || email

  # Their whole name, where there is room for it (the account menu, a
  # housemate's row); what we call them when they gave none.
  def full_name = [ first_name, last_name ].compact_blank.join(" ").presence || display_name

  private

  def time_zone_known
    errors.add(:time_zone, :inclusion) if time_zone.present? && ActiveSupport::TimeZone[time_zone].nil?
  end

  def prohibit_email_as_username
    if URI::MailTo::EMAIL_REGEXP.match?(username)
      errors.add(:username, :email_like)
    end
  end
end
