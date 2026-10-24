# frozen_string_literal: true

require "test_helper"

# The installation's limits, saved by the admin or started by the
# environment, and the open accounts (the secrets saved on /admin/settings have
# test/models/platform/setting_test.rb).
class PlatformTest < ActiveSupport::TestCase
  test "everything starts on and unlimited unless the environment says otherwise" do
    assert_predicate Platform, :assistant?
    assert_predicate Platform, :uploads?
    assert_predicate Platform, :pictures?
    assert_predicate Platform, :invitations?
    assert_predicate Platform, :push_notifications?
    assert_nil Platform.assistant_messages_per_day
    assert_nil Platform.book_lookups_per_day
    assert_nil Platform.household_size
    assert_nil Platform.invitations_per_member
    assert_predicate Platform, :release_check?
    assert_equal 50.gigabytes, Platform.files_quota
    assert_empty Platform.open_accounts
    assert_empty Platform.open_profiles
    assert_not Platform.open_account?(profiles(:alice))
    assert_not Platform.open_account?(nil)
  end

  test "a switch is off for off, false, no or 0, whatever the case; anything else leaves it on" do
    %w[off OFF false no 0].each { |value| with_env("UPLOADS" => value) { assert_not Platform.uploads?, value } }
    %w[on yes 1 maybe].each { |value| with_env("PICTURES" => value) { assert_predicate Platform, :pictures?, value } }
    with_env("INVITATIONS" => " off ") { assert_not Platform.invitations? }
    with_env("PUSH_NOTIFICATIONS" => "off") { assert_not Platform.push_notifications? }
    with_env("ASSISTANT" => "off") { assert_not Platform.assistant? }
  end

  test "a count is a whole number, else no limit" do
    with_env("ASSISTANT_MESSAGES_PER_DAY" => "30") { assert_equal 30, Platform.assistant_messages_per_day }
    with_env("BOOK_LOOKUPS_PER_DAY" => " 50 ") { assert_equal 50, Platform.book_lookups_per_day }
    with_env("ASSISTANT_MESSAGES_PER_DAY" => "0") { assert_equal 0, Platform.assistant_messages_per_day }
    [ "many", "-1", "1.5", "" ].each { |value| with_env("BOOK_LOOKUPS_PER_DAY" => value) { assert_nil Platform.book_lookups_per_day, value } }
    # None at all is what the invitations switch says, so a household of nobody is no limit.
    with_env("HOUSEHOLD_SIZE" => "0") { assert_nil Platform.household_size }
  end

  test "a size is a number of bytes, with or without a unit; anything else is the default" do
    assert_equal 512.megabytes, Platform::Size.parse("512 MB")
    assert_equal 1024, Platform::Size.parse("1024")
    assert_nil Platform::Size.parse("plenty")
    with_env("FILES_QUOTA" => "2KB") { assert_equal 2048, Platform.files_quota }
    with_env("FILES_QUOTA" => "plenty") { assert_equal 50.gigabytes, Platform.files_quota }
    with_env("FILES_QUOTA" => "0") { assert_equal 50.gigabytes, Platform.files_quota }
  end

  test "what the admin saved decides, whatever the environment says" do
    Platform::Setting.create!(uploads: false, assistant: true, assistant_messages_per_day: 12, files_quota: 3.gigabytes, household_size: 8)

    with_env("UPLOADS" => "on", "ASSISTANT" => "off", "ASSISTANT_MESSAGES_PER_DAY" => "30", "FILES_QUOTA" => "1GB", "HOUSEHOLD_SIZE" => "6",
             "BOOK_LOOKUPS_PER_DAY" => "50") do
      assert_not Platform.uploads?
      assert_predicate Platform, :assistant?
      assert_equal 12, Platform.assistant_messages_per_day
      assert_equal 3.gigabytes, Platform.files_quota
      assert_equal 8, Platform.household_size
      assert_nil Platform.book_lookups_per_day, "left empty on the row: no limit"
    end
  end

  test "a new row of settings starts from the environment, and keeps what it started with" do
    with_env("UPLOADS" => "off", "FILES_QUOTA" => "512MB", "BOOK_LOOKUPS_PER_DAY" => "50", "PICTURES" => "") do
      Platform::Setting.first_or_start.save!
    end

    assert_not Platform.uploads?
    assert_predicate Platform, :pictures?
    assert_equal 512.megabytes, Platform.files_quota
    assert_equal 50, Platform.book_lookups_per_day
    assert_equal Platform::Setting.sole, Platform::Setting.first_or_start
  end

  test "the open accounts are the usernames declared, those who joined, in that order" do
    demo_household
    with_env("OPEN_ACCOUNTS" => " Robin.demo, alex.demo ,ghost.demo, sam.demo") do
      assert_equal %w[robin.demo alex.demo ghost.demo sam.demo], Platform.open_accounts
      assert_equal %w[robin.demo alex.demo sam.demo], Platform.open_profiles.map(&:username)
      assert_equal "alex.demo", Platform.open_profile(" ALEX.demo")&.username
      assert_nil Platform.open_profile("ghost.demo")
      assert Platform.open_account?(Profile.find_by!(username: "sam.demo"))
      assert_not Platform.open_account?(profiles(:alice))

      # Named, but an invitation not yet accepted: no way in.
      Profile.find_by!(username: "sam.demo").update_columns(invitation_token: "waiting")
      assert_equal %w[robin.demo alex.demo], Platform.open_profiles.map(&:username)
    end
  end

  test "an admin is never an open account, even when named: that would be the installation for anyone" do
    demo_household.profiles.find_by!(username: "robin.demo").admin!
    with_env("OPEN_ACCOUNTS" => "alex.demo,robin.demo") do
      assert_equal %w[alex.demo], Platform.open_profiles.map(&:username)
      assert_nil Platform.open_profile("robin.demo")
      assert_not Platform.open_account?(Profile.find_by!(username: "robin.demo"))
    end
  end
end
