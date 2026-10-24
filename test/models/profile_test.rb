# frozen_string_literal: true

require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "removing someone is Profiles::Destroy: destroy on a person who kept things fails rather than half-remove them" do
    profile = profiles(:alice)
    assert_predicate profile.events, :exists?

    assert_raises(ActiveRecord::InvalidForeignKey) { profile.destroy }
    assert Profile.exists?(profile.id)
  end

  test "signing in finds a person by username or email in any case; Devise's own lookups by either too" do
    alice = profiles(:alice)
    assert_equal alice, Profile.find_for_database_authentication(login: " #{alice.username.upcase} ")
    assert_equal alice, Profile.find_for_database_authentication(login: alice.email.upcase)
    assert_equal alice, Profile.find_for_database_authentication(email: alice.email)
    assert_nil Profile.find_for_database_authentication(remember_token: "x")
  end

  test "a username chosen in capitals is found however it is typed, by sign-in and by the open accounts" do
    alice = profiles(:alice)
    alice.update!(username: "Alice.Example")

    assert_equal alice, Profile.find_for_database_authentication(login: "alice.EXAMPLE")
    assert_equal [ alice ], Profile.with_username([ " ALICE.example ", "nobody" ]).to_a
  end

  test "the database refuses a username that differs from another only in case" do
    error = assert_raises(ActiveRecord::RecordNotUnique) do
      profiles(:bob).update_columns(username: profiles(:alice).username.upcase)
    end
    assert_includes error.message, "index_profiles_on_lower_username"
  end

  test "a time zone the browser names must be one we know" do
    alice = profiles(:alice)
    assert_not alice.tap { _1.time_zone = "Mars/Olympus" }.valid?
    assert alice.errors.of_kind?(:time_zone, :inclusion)
  end

  test "an invitation has no username yet and is valid; a person who joined needs one, never an email" do
    invited = Profile.invite!({ email: "erin@example.com", household: households(:example) }, profiles(:alice)) { _1.skip_invitation = true }
    assert_predicate invited, :invitation_pending?
    assert_predicate invited, :valid?, invited.errors.full_messages.to_sentence

    joined = profiles(:alice)
    joined.username = nil
    assert_not joined.valid?
    assert joined.errors.of_kind?(:username, :blank)

    joined.username = "alice@example.com"
    assert_not joined.valid?
    assert_includes joined.errors[:username], I18n.t("activerecord.errors.models.profile.attributes.username.email_like")
  end

  test "someone is called by their first name, else their username; their full name falls back to that" do
    alice = profiles(:alice)
    assert_equal "Alice", alice.display_name
    assert_equal "#{alice.first_name} #{alice.last_name}", alice.full_name

    alice.last_name = nil
    assert_equal "Alice", alice.full_name
    alice.first_name = nil
    assert_equal alice.username, alice.display_name
    assert_equal alice.username, alice.full_name
  end
end
