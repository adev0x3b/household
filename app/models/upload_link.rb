# frozen_string_literal: true

# A public link: one file to download for anyone who has it, no account needed.
# The owner makes it (UploadLink.mint) and gets the token once; the
# database keeps only its SHA-256 digest, so a copy of the database can't
# download anything. Each link has an end (`expires_at`, MAX_LIFETIME at
# most), a number of downloads (`max_downloads`, one by default; nil is no
# limit), maybe a password, and can be revoked. Every use, and every refusal,
# is an UploadActivity on the file.
#
# A download is counted when it starts (`consume!`): a one-time link is
# spent by the first press, the way WeTransfer's are. The press hands over
# a ticket good for CONTINUATION_WINDOW and bound to the presser's session
# (UploadLinks::PublicController), so a download cut short is picked up where it
# stopped without counting again, while the ticket's address passed on to
# anyone else opens nothing.
#
# A password is 8 characters at least, and after MAX_WRONG_PASSWORDS wrong
# ones the link closes itself: the per-address rate limit slows guessing,
# this ends it, whatever the addresses, over a link's 30 days.
class UploadLink < ApplicationRecord
  has_secure_password :password, validations: false

  LIFETIMES = [ 1, 7, 30 ].freeze # days
  DEFAULT_LIFETIME = 7
  MAX_LIFETIME = 30.days
  LIMITS = [ 1, 5, nil ].freeze # downloads; nil: no limit
  DEFAULT_LIMIT = 1
  CONTINUATION_WINDOW = 1.hour
  PASSWORD_LENGTH = 8..72
  MAX_WRONG_PASSWORDS = 10
  STATES = %i[active exhausted expired revoked].freeze

  belongs_to :upload
  belongs_to :profile
  has_many :upload_activities, dependent: :nullify

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :max_downloads, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :password, length: { in: PASSWORD_LENGTH }, allow_nil: true
  validate :lifetime_within_bounds
  validate :only_a_ready_file, on: :create

  scope :live, -> { where(revoked_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # A fresh link and its token: the token is readable only now.
  def self.mint(upload:, by:, lifetime_days: DEFAULT_LIFETIME, max_downloads: DEFAULT_LIMIT, password: nil)
    token = SecureRandom.urlsafe_base64(32)
    link = upload.upload_links.create(profile: by, token_digest: digest(token), expires_at: lifetime_days.to_i.days.from_now,
                                      max_downloads: max_downloads, password: password.presence)
    [ link, token ]
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_by_token(token) = token.present? ? find_by(token_digest: digest(token)) : nil

  def expired? = expires_at <= Time.current

  def revoked? = revoked_at.present?

  def exhausted? = max_downloads.present? && downloads_count >= max_downloads

  def protected? = password_digest.present?

  def usable? = !revoked? && !expired? && !exhausted? && upload.ready?

  def state
    if revoked? then :revoked
    elsif expired? then :expired
    elsif exhausted? then :exhausted
    else :active
    end
  end

  # One more download, counted now: true when the link was still good, false
  # when it wasn't (two people pressing at once: one of them gets the file).
  def consume!
    with_lock do
      next false unless usable?

      update!(downloads_count: downloads_count + 1, last_used_at: Time.current)
      true
    end
  end

  # A wrong password at the link: on the file's trail, and the link closes
  # after MAX_WRONG_PASSWORDS of them.
  def refuse_password!(request:)
    UploadActivity.record(upload, :link_refused, link: self, request:, reason: "wrong_password")
    return if wrong_passwords < MAX_WRONG_PASSWORDS

    revoke!
    UploadActivity.record(upload, :link_locked, link: self, wrong_passwords: MAX_WRONG_PASSWORDS)
  end

  def wrong_passwords = upload_activities.link_refused.where("data ->> 'reason' = 'wrong_password'").count

  # The rest of a download already started, within the window: not counted.
  def continuation_allowed? = !revoked? && last_used_at.present? && last_used_at > CONTINUATION_WINDOW.ago && upload.ready?

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  private

  def only_a_ready_file
    errors.add(:upload, :not_ready) if upload && !upload.ready?
  end

  def lifetime_within_bounds
    return if expires_at.blank?

    errors.add(:expires_at, :too_far) if expires_at > (created_at || Time.current) + MAX_LIFETIME + 1.minute
    errors.add(:expires_at, :past) if new_record? && expires_at <= Time.current
  end
end
