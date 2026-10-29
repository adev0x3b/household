# frozen_string_literal: true

class Profile < ApplicationRecord
  # Invite only: nobody signs up. A profile is created by an invitation
  # (Households::Invite) and becomes usable when it is accepted. A password
  # is reset by a link from the household page (Profiles::PasswordLink), or
  # one mailed to the person's confirmed address when they forget it
  # (Profiles::RequestPasswordLink); how long, how many tries, how idle:
  # config/initializers/devise.rb.
  devise :invitable, :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable,
         :lockable, :timeoutable

  # How long a link that confirms an address works.
  EMAIL_CONFIRMATION_FOR = 24.hours
  # How long the link in a reminder mail that stops them all works.
  EMAIL_UNSUBSCRIPTION_FOR = 90.days
  # How long a link to set a password works when it is mailed or printed on
  # the server, where more than the person may read it. One the household's
  # owner or the admin hands over lasts Devise's reset_password_within.
  SHORT_PASSWORD_LINK_FOR = 30.minutes

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

  normalizes :email, :unconfirmed_email, with: ->(email) { email.strip.downcase }

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

  # Whatever writes the profile: another address ends the links made for
  # the one before (to confirm it, to set a password) and is confirmed only
  # when the save is its confirmation; another address waiting ends the link
  # made for the one before it; and a new password ends a change of address
  # still waiting, so whoever had the account can't finish it.
  before_update :leave_the_old_address, if: :will_save_change_to_email?
  before_update :forget_the_confirmation_link, if: :will_save_change_to_unconfirmed_email?
  before_update :end_a_change_of_address, if: :will_save_change_to_encrypted_password?

  def login
    @login || self.username || self.email
  end

  # Devise never mails: every mail goes through the outbox (Emails), within
  # the installation's budgets and in the person's language. Whatever of
  # Devise's would mail fails here instead of sending around them.
  def send_devise_notification(notification, *)
    raise NotImplementedError, "Devise would mail #{notification}: the app's mail goes through Emails::Enqueue"
  end

  # A token for the link that sets a new password, handed over by the
  # household's owner or the admin (Profiles::PasswordLink), readable only
  # now: the database keeps its digest, and an earlier link stops working.
  # Its time is written even when it reads empty here, since a link mailed
  # since this was read would otherwise lend it its 30 minutes.
  def password_link_token!
    self.reset_password_expires_at = nil
    reset_password_expires_at_will_change!
    set_reset_password_token
  end

  # The same, for a link that goes by mail (Emails::Kinds::PasswordLink) or
  # is printed on the server (admin:password_link): it works for
  # SHORT_PASSWORD_LINK_FOR.
  def short_password_link_token!(now = Time.current)
    self.reset_password_expires_at = now + SHORT_PASSWORD_LINK_FOR
    set_reset_password_token
  end

  # Whether a short link is out and still works.
  def short_password_link_open?(now = Time.current)
    reset_password_token.present? && reset_password_expires_at.present? && reset_password_expires_at > now
  end

  # Whichever link there is stops working.
  def forget_password_link! = update_columns(reset_password_token: nil, reset_password_sent_at: nil, reset_password_expires_at: nil)

  # Devise's question when a link is opened and when it sets the password:
  # a short link's own time, else Devise's.
  def reset_password_period_valid?
    reset_password_expires_at ? reset_password_expires_at.future? : super
  end

  # Whether this is their password, counted as a sign-in is: a wrong one
  # brings Devise's lock nearer, and the right one starts the count again.
  # Asked before something only the person may do (Admin::Sudo, the Account
  # page), so a stolen session can't guess its way there.
  def try_password(password)
    return false unless password.present? && valid_for_authentication? { valid_password?(password) }

    reset_failed_attempts!
    true
  end

  # Mail goes to an address once the person has shown it is theirs: a link
  # mailed to it, opened in their own session and confirmed with their
  # password (Accounts::EmailConfirmation).
  def email_confirmed? = email_confirmed_at.present?

  # The address a confirmation link is for: a new one waiting, else the one in use.
  def address_to_confirm = unconfirmed_email.presence || email

  # A token for the link that confirms the address (Emails::Kinds::EmailConfirmation),
  # readable only now: the database keeps its digest, with when it was made
  # and for which address, and an earlier link stops working.
  def email_confirmation_token!
    token, digest = Devise.token_generator.generate(Profile, :email_confirmation_digest)
    update_columns(email_confirmation_digest: digest, email_confirmation_sent_at: Time.current,
                   email_confirmation_address_digest: Profile.address_digest(address_to_confirm))
    token
  end

  # Its confirmation link stops working.
  def forget_email_confirmation_link! = update_columns(email_confirmation_digest: nil, email_confirmation_sent_at: nil, email_confirmation_address_digest: nil)

  # Whose confirmation link this is, while it still confirms the address it
  # was made for; nil otherwise.
  def self.with_email_confirmation_token(token, now: Time.current)
    return if token.blank?

    profile = find_by(email_confirmation_digest: Devise.token_generator.digest(Profile, :email_confirmation_digest, token.to_s))
    profile if profile&.email_confirmation_open?(now)
  end

  # An address kept only to compare with: a token's, never written out.
  def self.address_digest(address) = OpenSSL::Digest::SHA256.hexdigest(address.to_s.strip.downcase)

  # The link in a reminder mail that stops every reminder by email
  # (EmailUnsubscriptionsController), working while the address it went to
  # is the one confirmed. Its token can be read, so it holds when the
  # address was confirmed, which every confirmed address has its own of,
  # rather than the address.
  generates_token_for :email_unsubscription, expires_in: EMAIL_UNSUBSCRIPTION_FOR do
    email_confirmed_at&.to_i
  end

  # Whether its confirmation link still works: made less than
  # EMAIL_CONFIRMATION_FOR ago, for the address that is still to confirm.
  def email_confirmation_open?(now = Time.current)
    email_confirmation_sent_at.present? && email_confirmation_sent_at > now - EMAIL_CONFIRMATION_FOR &&
      email_confirmation_address_digest == Profile.address_digest(address_to_confirm)
  end

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

  def leave_the_old_address
    self.email_confirmed_at = nil unless will_save_change_to_email_confirmed_at?
    self.reset_password_token = nil
    self.reset_password_sent_at = nil
    self.reset_password_expires_at = nil
    forget_the_confirmation_link
  end

  def end_a_change_of_address
    self.unconfirmed_email = nil
    forget_the_confirmation_link
  end

  def forget_the_confirmation_link
    self.email_confirmation_digest = nil
    self.email_confirmation_sent_at = nil
    self.email_confirmation_address_digest = nil
  end

  def time_zone_known
    errors.add(:time_zone, :inclusion) if time_zone.present? && ActiveSupport::TimeZone[time_zone].nil?
  end

  def prohibit_email_as_username
    if URI::MailTo::EMAIL_REGEXP.match?(username)
      errors.add(:username, :email_like)
    end
  end
end
