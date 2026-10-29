# frozen_string_literal: true

require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "removing someone is Profiles::Destroy: destroy on a person who kept things fails rather than half-remove them" do
    profile = profiles(:alice)
    assert_predicate profile.events, :exists?

    assert_raises(ActiveRecord::InvalidForeignKey) { profile.destroy }
    assert Profile.exists?(profile.id)
  end

  test "Devise never mails: what it would mail fails instead of going around the outbox" do
    error = assert_raises(NotImplementedError) { profiles(:alice).send_reset_password_instructions }

    assert_match(/reset_password_instructions/, error.message)
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

  test "a password tried counts as a sign-in: a wrong one brings the lock nearer, the right one starts the count again" do
    alice = profiles(:alice).tap { _1.update!(password: "alice's long password", password_confirmation: "alice's long password") }

    assert_not alice.try_password("not the password")
    assert_not alice.try_password("")
    assert_equal 1, alice.reload.failed_attempts, "an empty password is no try"

    assert alice.try_password("alice's long password")
    assert_equal 0, alice.reload.failed_attempts
  end

  test "ten wrong passwords lock the account, and then even the right one is refused" do
    alice = profiles(:alice).tap { _1.update!(password: "alice's long password", password_confirmation: "alice's long password") }
    10.times { alice.try_password("not the password") }

    assert_predicate alice.reload, :access_locked?
    assert_not alice.try_password("alice's long password")
  end

  test "a link that confirms an address works for a day, once, and only while that address is the one to confirm" do
    alice = profiles(:alice)
    token = alice.email_confirmation_token!

    assert_equal alice, Profile.with_email_confirmation_token(token)
    assert_nil Profile.with_email_confirmation_token(token, now: Profile::EMAIL_CONFIRMATION_FOR.from_now + 1.second)
    assert_nil Profile.with_email_confirmation_token("#{token}x")
    assert_nil Profile.with_email_confirmation_token("")
    assert_not_equal token, alice.reload.email_confirmation_digest, "the database keeps a digest"

    alice.update!(unconfirmed_email: "alice@new.example")
    assert_nil Profile.with_email_confirmation_token(token), "another address waits now"

    newer = alice.email_confirmation_token!
    assert_equal alice, Profile.with_email_confirmation_token(newer)
    alice.update_columns(unconfirmed_email: "alice@other.example")
    assert_nil Profile.with_email_confirmation_token(newer), "made for an address no longer waiting, however that changed"
  end

  test "another address isn't confirmed, ends the links made for the old one, and is confirmed only by its confirmation" do
    alice = profiles(:alice)
    alice.update!(email_confirmed_at: 1.day.ago)
    reset_token = alice.short_password_link_token!
    alice.email_confirmation_token!

    alice.update!(email: " Alice@New.example ")

    alice.reload
    assert_nil alice.reset_password_expires_at
    assert_equal "alice@new.example", alice.email
    assert_not alice.email_confirmed?
    assert_nil alice.email_confirmation_digest
    assert_nil Profile.with_reset_password_token(reset_token), "a link to set the password made for the old address stops working"

    alice.update!(email: "alice@newest.example", email_confirmed_at: Time.current)
    assert_predicate alice.reload, :email_confirmed?
  end

  test "a link to set a password lasts two days when handed over, half an hour when mailed or printed, and the newest wins" do
    alice = profiles(:alice)
    handed = alice.password_link_token!
    short = alice.short_password_link_token!

    assert_nil Profile.with_reset_password_token(handed)
    assert_predicate alice, :short_password_link_open?
    travel Profile::SHORT_PASSWORD_LINK_FOR + 1.second
    assert_not alice.short_password_link_open?
    assert_not Profile.with_reset_password_token(short).reset_password_period_valid?

    handed = alice.password_link_token!
    travel 1.day
    assert_predicate Profile.with_reset_password_token(handed), :reset_password_period_valid?
    alice.forget_password_link!
    assert_nil Profile.with_reset_password_token(handed)
  end

  test "a new password ends a change of address still waiting, and its link" do
    alice = profiles(:alice)
    alice.update!(unconfirmed_email: "alice@new.example")
    token = alice.email_confirmation_token!

    alice.update!(password: "another long password", password_confirmation: "another long password")

    assert_nil alice.reload.unconfirmed_email
    assert_nil Profile.with_email_confirmation_token(token)
  end
end
