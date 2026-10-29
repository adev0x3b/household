# frozen_string_literal: true

# The installation's settings as the admin saved them, in the first setup or
# on /admin/settings: one row. Its secrets are encrypted and never shown
# back. A secret left nil comes from the environment, if anywhere. The
# limits are the row's alone once it exists: the environment's values are
# only where a new row starts (Platform).
class Platform::Setting < ApplicationRecord
  PASSWORDS = %i[demo_password smtp_password].freeze

  encrypts :google_books_api_key, :deploy_dispatch_token, :demo_password, :smtp_password

  belongs_to :updated_by, class_name: "Profile", optional: true

  normalizes :google_books_api_key, :deploy_dispatch_token, :demo_password, :smtp_password, :smtp_host, :smtp_username, :smtp_tls, :mail_from,
             with: ->(value) { value.to_s.strip.presence }

  # The demo's members sign in with it: Devise's rules apply (Demo::Seeder would fail otherwise).
  validates :demo_password, length: { in: Devise.password_length }, allow_nil: true
  validates :assistant_messages_per_day, :book_lookups_per_day, :reminder_mails_per_day,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :files_quota, :household_size, :invitations_per_member, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :mails_per_hour, numericality: { only_integer: true, greater_than_or_equal_to: Platform.limit(:mails_per_hour).minimum }, allow_nil: true
  validates :mails_per_day, numericality: { only_integer: true, greater_than_or_equal_to: Platform.limit(:mails_per_day).minimum }, allow_nil: true
  validates :smtp_port, numericality: { only_integer: true, in: 1..65_535 }, allow_nil: true
  validates :smtp_tls, inclusion: { in: Emails::RelaySettings::TLS_MODES }, allow_nil: true

  # The configuration in use changed: the next read finds the row again.
  after_commit { self.class.forget_saved }

  # The row, or a new one holding the limits' starting values, unsaved.
  def self.first_or_start = first || new(Platform.starting_values)

  # The saved row, or nil while the starting values decide.
  def self.saved
    found = (Current.platform_setting ||= first || :none)
    found == :none ? nil : found
  end

  # The next read finds the row again, as a job that runs for minutes
  # does, to follow what the admin saved meanwhile (Emails::Drain).
  def self.forget_saved
    Current.platform_setting = nil
  end

  # A saved key's last four characters, all a page ever shows of it, so the
  # admin can tell which one is saved; nil for a password, of which a page
  # shows nothing, since every character shown is one less to guess.
  def hint(key) = (public_send(key)&.last(4) unless PASSWORDS.include?(key))
end
