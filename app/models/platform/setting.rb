# frozen_string_literal: true

# The installation's settings as the admin saved them, in the first setup or
# on /admin/settings: one row. Its secrets are encrypted and never shown
# back. A secret left nil comes from the environment, if anywhere. The
# limits are the row's alone once it exists: the environment's values are
# only where a new row starts (Platform).
class Platform::Setting < ApplicationRecord
  encrypts :google_books_api_key, :deploy_dispatch_token, :demo_password

  belongs_to :updated_by, class_name: "Profile", optional: true

  normalizes :google_books_api_key, :deploy_dispatch_token, :demo_password, with: ->(value) { value.to_s.strip.presence }

  # The demo's members sign in with it: Devise's rules apply (Demo::Seeder would fail otherwise).
  validates :demo_password, length: { in: Devise.password_length }, allow_nil: true
  validates :assistant_messages_per_day, :book_lookups_per_day, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :files_quota, :household_size, :invitations_per_member, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # The configuration in use changed: the next read finds the row again.
  after_commit { Current.platform_setting = nil }

  # The row, or a new one holding the limits' starting values, unsaved.
  def self.first_or_start = first || new(Platform.starting_values)

  # The saved row, or nil while the starting values decide.
  def self.saved
    found = (Current.platform_setting ||= first || :none)
    found == :none ? nil : found
  end

  # A saved secret's last four characters, all a page ever shows of it.
  def hint(key) = public_send(key)&.last(4)
end
