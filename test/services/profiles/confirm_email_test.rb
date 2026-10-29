# frozen_string_literal: true

require "test_helper"

# Confirming an address from its link, signed in as its person: once, for
# the address it was made for, and never one someone else has meanwhile.
class Profiles::ConfirmEmailTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  test "a new address waiting takes over, confirmed, and the one confirmed before hears of it" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@new.example")
    token = @alice.email_confirmation_token!

    result = Profiles::ConfirmEmail.call(@alice, token: token)

    assert_predicate result, :success?
    @alice.reload
    assert_equal "alice@new.example", @alice.email
    assert_nil @alice.unconfirmed_email
    assert_in_delta Time.current, @alice.email_confirmed_at, 1.second
    assert_equal({ "to" => "alice@example.com" }, OutgoingEmail.email_changed.sole.data)
    assert_equal :expired, Profiles::ConfirmEmail.call(@alice, token: token).error, "a link works once"
  end

  test "the address in use is confirmed, and a person with no language gets the page's" do
    @alice.update!(locale: nil)
    token = @alice.email_confirmation_token!

    assert_predicate Profiles::ConfirmEmail.call(@alice, token: token, locale: :it), :success?

    @alice.reload
    assert_predicate @alice, :email_confirmed?
    assert_equal "it", @alice.locale
    assert_not OutgoingEmail.exists?, "nobody to tell: the address didn't change"
  end

  test "a language the person picked stays theirs" do
    @alice.update!(locale: "en")
    Profiles::ConfirmEmail.call(@alice, token: @alice.email_confirmation_token!, locale: :it)

    assert_equal "en", @alice.reload.locale
  end

  test "a link to set a password made for the old address since the person's page was read ends with it" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@new.example")
    token = @alice.email_confirmation_token!
    signed_in = Profile.find(@alice.id)
    Profile.find(@alice.id).short_password_link_token!

    assert_predicate Profiles::ConfirmEmail.call(signed_in, token: token), :success?

    assert_nil @alice.reload.reset_password_token
  end

  test "a link out of date, someone else's, or for an address someone has since taken confirms nothing" do
    token = @alice.email_confirmation_token!
    assert_equal :expired, Profiles::ConfirmEmail.call(@alice, token: token, now: 25.hours.from_now).error
    assert_equal :not_yours, Profiles::ConfirmEmail.call(profiles(:bob), token: token).error

    @alice.update!(unconfirmed_email: "taken@example.com")
    token = @alice.email_confirmation_token!
    profiles(:bob).update!(email: "taken@example.com")
    assert_equal :taken, Profiles::ConfirmEmail.call(@alice, token: token).error

    assert_not @alice.reload.email_confirmed?
    assert_equal "alice@example.com", @alice.email
  end
end
