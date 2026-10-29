# frozen_string_literal: true

# What is set for the whole installation, read through here and nowhere else.
#
# The admin's secrets, saved on /admin/settings (Platform::Setting): the
# bookshelf's Google Books key, the GitHub token behind /admin/deployment's
# buttons, the demo accounts' password, the mail relay's password. Each is
# read, first set wins, from:
#   1. the saved row — an admin typed it on the page
#   2. the environment: GOOGLE_BOOKS_API_KEY, DEPLOY_DISPATCH_TOKEN, DEMO_PASSWORD,
#      SMTP_PASSWORD (.env in development; the way before the page existed)
# The rest of the mail relay is read the same way, field by field, and shown
# back on the page (Emails::RelaySettings): SMTP_HOST, SMTP_PORT,
# SMTP_USERNAME, SMTP_TLS, MAIL_FROM.
#
# The installation's limits: what this copy lets its people do. The admin
# sets each in the first setup and on /admin/settings, saved on the same
# row, which decides from then on. The environment only gives a limit its
# starting value: until there is a row, and on the row when it is made
# (Platform::Setting.first_or_start). That is how a destination begins: the
# demo's are in config/deploy.demo.yml, and every destination's names are
# Provision::Settings. A limit no variable names starts on and unlimited,
# except the mail budgets, which start at their defaults: mail always has one.
#   ASSISTANT=off                  no assistant: its tab is gone and its pages are a 404 (the admin's settings page stays)
#   UPLOADS=off                    nobody uploads a file or makes a public link; what is there is seen and downloaded
#   PICTURES=off                   no pictures in messages, no photos to the assistant
#   INVITATIONS=off                members invite nobody (the admin still does)
#   PUSH_NOTIFICATIONS=off         no device subscribes, even with VAPID keys
#   RELEASE_CHECK=off              the copy never asks GitHub for a newer release
#   ASSISTANT_MESSAGES_PER_DAY=30  what a household may ask the assistant in a day
#   BOOK_LOOKUPS_PER_DAY=50        the Open Library lookups a household gets in a day
#   FILES_QUOTA=50GB               what a household may keep in Files
#   HOUSEHOLD_SIZE=20              the people a household may hold, invitations waiting included
#   INVITATIONS_PER_MEMBER=5       the people one member may invite into their household
#   OUTGOING_MAIL=off              nothing is mailed, even with a relay set
#   MAILS_PER_HOUR=6               the mail the installation sends in an hour (at least 2)
#   MAILS_PER_DAY=40               the mail the installation sends in a day (at least 6)
#   REMINDER_MAILS_PER_DAY=20      the reminder mails a household gets in a day
# OPEN_ACCOUNTS=alex.demo,… names the accounts anyone enters without a
# password (DemosController), from the environment alone.
# The assistant's own settings are Assistant (/assistant/settings).
module Platform
  KEYS = %i[google_books_api_key deploy_dispatch_token demo_password smtp_password].freeze
  ENV_NAMES = { google_books_api_key: "GOOGLE_BOOKS_API_KEY", deploy_dispatch_token: "DEPLOY_DISPATCH_TOKEN",
                demo_password: "DEMO_PASSWORD", smtp_password: "SMTP_PASSWORD", smtp_host: "SMTP_HOST", smtp_port: "SMTP_PORT",
                smtp_username: "SMTP_USERNAME", smtp_tls: "SMTP_TLS", mail_from: "MAIL_FROM" }.freeze
  DEFAULT_DEMO_PASSWORD = "demo-household"

  LIMITS = [
    Switch.new(:assistant, env: "ASSISTANT"),
    Switch.new(:uploads, env: "UPLOADS"),
    Switch.new(:pictures, env: "PICTURES"),
    Switch.new(:invitations, env: "INVITATIONS"),
    Switch.new(:push_notifications, env: "PUSH_NOTIFICATIONS"),
    Switch.new(:release_check, env: "RELEASE_CHECK"),
    Count.new(:assistant_messages_per_day, env: "ASSISTANT_MESSAGES_PER_DAY"),
    Count.new(:book_lookups_per_day, env: "BOOK_LOOKUPS_PER_DAY"),
    Size.new(:files_quota, env: "FILES_QUOTA", default: 50.gigabytes),
    Count.new(:household_size, env: "HOUSEHOLD_SIZE", minimum: 1),
    Count.new(:invitations_per_member, env: "INVITATIONS_PER_MEMBER", minimum: 1),
    Switch.new(:outgoing_mail, env: "OUTGOING_MAIL"),
    # Reminders leave the last of each hour and the last five of each day to
    # account mail (Emails::RelayAllowance), so each budget leaves them one.
    Count.new(:mails_per_hour, env: "MAILS_PER_HOUR", minimum: 2, default: 6),
    Count.new(:mails_per_day, env: "MAILS_PER_DAY", minimum: 6, default: 40),
    Count.new(:reminder_mails_per_day, env: "REMINDER_MAILS_PER_DAY", default: 20)
  ].index_by(&:name).freeze
  OPEN_ACCOUNTS = "OPEN_ACCOUNTS"

  def self.table_name_prefix
    "platform_"
  end

  def self.saved = Platform::Setting.saved

  def self.google_books_api_key = value(:google_books_api_key)
  def self.deploy_dispatch_token = value(:deploy_dispatch_token)
  def self.demo_password = value(:demo_password) || DEFAULT_DEMO_PASSWORD

  # What the setup page's one-time code must hash to (SetupCode), while nobody
  # has signed in yet; nil when no code was made.
  def self.setup_code_digest = saved&.setup_code_digest

  # The saved value, else the environment's, else nil: a secret, or a field
  # of the mail relay.
  def self.value(key) = saved_value(key) || env_value(key)

  # The value the admin saved, never the environment's.
  def self.saved_value(key) = saved&.public_send(key).presence

  # The environment's value, whatever is saved.
  def self.env_value(key) = ENV[ENV_NAMES.fetch(key)].presence

  # Where the value in use comes from, for the page: :saved, :env or nil.
  def self.source(key)
    if saved_value(key) then :saved
    elsif env_value(key) then :env
    end
  end

  # --- The limits ----------------------------------------------------------------

  def self.limit(name) = LIMITS.fetch(name)

  # What a new row of settings holds for each limit, by column.
  def self.starting_values = LIMITS.transform_values(&:starting_value)

  def self.assistant? = limit(:assistant).value(saved)
  def self.uploads? = limit(:uploads).value(saved)
  def self.pictures? = limit(:pictures).value(saved)
  def self.invitations? = limit(:invitations).value(saved)
  def self.push_notifications? = limit(:push_notifications).value(saved)
  def self.release_check? = limit(:release_check).value(saved)

  def self.outgoing_mail? = limit(:outgoing_mail).value(saved)

  # A household's messages to the assistant in a day; nil: no limit.
  def self.assistant_messages_per_day = limit(:assistant_messages_per_day).value(saved)

  # A household's Open Library lookups in a day; nil: no limit.
  def self.book_lookups_per_day = limit(:book_lookups_per_day).value(saved)

  # What a household may keep in Files, in bytes.
  def self.files_quota = limit(:files_quota).value(saved)

  # The people a household may hold, invitations waiting included; nil: no limit.
  def self.household_size = limit(:household_size).value(saved)

  # The people one member may invite into their own household, an
  # invitation taken back not counted; nil: no limit.
  def self.invitations_per_member = limit(:invitations_per_member).value(saved)

  # The mail the installation may send in a rolling hour and day, every kind
  # together (Emails::RelayAllowance).
  def self.mails_per_hour = limit(:mails_per_hour).value(saved)
  def self.mails_per_day = limit(:mails_per_day).value(saved)

  # The reminder mails a household's people get in a rolling day, together
  # (Emails::ReminderAllowance).
  def self.reminder_mails_per_day = limit(:reminder_mails_per_day).value(saved)

  # --- The open accounts ---------------------------------------------------------

  # The usernames anyone may enter as, without a password: the demo's three
  # on the demo installation, none anywhere else.
  def self.open_accounts = ENV[OPEN_ACCOUNTS].to_s.split(",").map { _1.strip.downcase }.compact_blank

  # Is this profile one of them? An admin never is, even when named:
  # entering as them without a password would hand anyone the installation.
  def self.open_account?(profile)
    profile.present? && !profile.admin? && open_accounts.include?(profile.username.downcase)
  end

  # The open accounts that exist and have joined, in the order declared,
  # without an admin: the sign-in page's buttons, the banner's.
  def self.open_profiles
    names = open_accounts
    return [] if names.empty?

    Profile.joined.not_admin.with_username(names).sort_by { names.index(_1.username.downcase) }
  end

  # The open account with this username, else nil.
  def self.open_profile(username) = open_profiles.find { _1.username.casecmp?(username.to_s.strip) }
end
