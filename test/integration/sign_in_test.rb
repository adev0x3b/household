# frozen_string_literal: true

require "test_helper"

# Signing in and keeping an account safe: how long a password is, what
# many wrong ones do, how long an idle session lasts, and how a forgotten
# password is replaced — a link from the household page, never an email.
class SignInTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD) }
  end

  teardown { travel_back }

  test "ten wrong passwords from anywhere lock the account for a quarter of an hour, and it never says so" do
    Devise.maximum_attempts.times { |i| sign_in_as(@alice, "wrong-#{i}", from: "203.0.113.#{i + 1}") }
    assert_predicate @alice.reload, :access_locked?

    sign_in_as(@alice, PASSWORD, from: "198.51.100.7")
    assert_signed_out
    locked = toasts
    sign_in_as(Profile.new(username: "nobody"), PASSWORD, from: "198.51.100.8")
    assert_equal [ I18n.t("devise.failure.invalid", authentication_keys: "login") ], locked
    assert_equal toasts, locked, "a locked account reads like a wrong password, or no account at all"

    travel 16.minutes
    sign_in_as(@alice, PASSWORD, from: "198.51.100.9")
    assert_signed_in
  end

  test "a password link opens a locked account" do
    @alice.lock_access!
    token = password_link_for(@alice)

    put profile_password_path, params: { profile: { reset_password_token: token, password: "another-long-one", password_confirmation: "another-long-one" } }

    assert_not @alice.reload.access_locked?
    assert @alice.valid_password?("another-long-one")
  end

  test "a new password is twelve characters at least, and the page says so" do
    token = password_link_for(@alice)
    get edit_profile_password_path(reset_password_token: token)
    assert_select "input#profile_password[minlength='12'][aria-describedby='profile_password_rule']"
    assert_select "#profile_password_rule", text: I18n.t("password_field.rule", count: 12)

    put profile_password_path, params: { profile: { reset_password_token: token, password: "elevenchars", password_confirmation: "elevenchars" } }

    assert_response :unprocessable_content
    assert_not @alice.reload.valid_password?("elevenchars")
  end

  test "a page asked for signed out asks to sign in, and offers no sign-up the app doesn't have" do
    get recipes_path
    follow_redirect!

    assert_signed_out
    assert_equal [ "Sign in to continue." ], toasts
  end

  test "twelve idle hours end a session" do
    sign_in_as(@alice, PASSWORD, remember: false)
    travel 13.hours
    get root_path
    follow_redirect! while response.redirect?

    assert_signed_out
    assert_equal [ I18n.t("devise.failure.timeout") ], toasts
  end

  # Signed in before any travel: a frozen clock makes the remember cookie as
  # old as its own record, which Devise refuses.
  test "ticking Remember me keeps a session past the idle hours" do
    sign_in_as(@alice, PASSWORD, remember: true)
    travel 13.hours
    get root_path

    assert_response :success
  end

  test "the sign-in page ticks Remember me, and says how a forgotten password is replaced: no email form exists" do
    get new_profile_session_path

    assert_select "input[type=checkbox][name='profile[remember_me]'][checked]"
    assert_select ".auth-card__note", text: I18n.t("sessions.new.forgot")
    assert_select "a[href*='password']", count: 0

    get "#{Rails.configuration.x.mount_path}/profiles/password/new"
    assert_response :not_found
  end

  test "its password field has a label, and the button that shows it says what it does" do
    get new_profile_session_path

    assert_select "label.is-sr-only[for=profile_password]"
    assert_select "input#profile_password[autocomplete=current-password]:not([minlength])"
    assert_select "button.auth-card__toggle-password[aria-label=?][aria-pressed=false]", I18n.t("password_field.show")
  end

  test "guessing a link's token is slowed like signing in" do
    counting_rate_limits do
      page = edit_profile_password_url(reset_password_token: "guess")
      11.times { put profile_password_path, params: { profile: { reset_password_token: "guess", password: PASSWORD, password_confirmation: PASSWORD } }, headers: { "Referer" => page } }
      assert_response :see_other
      follow_redirect!
      assert_toast I18n.t("rate_limit.exceeded")

      page = accept_profile_invitation_url(invitation_token: "guess")
      11.times { put profile_invitation_path, params: { profile: { invitation_token: "guess", username: "erin", password: PASSWORD, password_confirmation: PASSWORD } }, headers: { "Referer" => page } }
      assert_redirected_to page, "sent back, not to sign-in as a dead link is: the action never ran"
      assert_equal I18n.t("rate_limit.exceeded"), flash[:alert]
    end
  end

  test "signing out empties the browser's cache of the site, so Back can't show the last person's pages" do
    sign_in_as(@alice, PASSWORD)

    delete destroy_profile_session_path

    assert_equal '"cache"', response.headers["Clear-Site-Data"]
    assert_redirected_to root_path
  end

  test "accepting with a token that opens no invitation says the link is dead" do
    put profile_invitation_path, params: { profile: { invitation_token: "used-or-guessed", username: "erin", password: PASSWORD, password_confirmation: PASSWORD } }

    assert_redirected_to new_profile_session_path
    follow_redirect!
    assert_equal [ I18n.t("devise.invitations.invitation_token_invalid") ], toasts
  end

  private

  def sign_in_as(profile, password, from: "127.0.0.1", remember: false)
    post profile_session_path, params: { profile: { login: profile.username, password:, remember_me: remember ? "1" : "0" } },
                               env: { "REMOTE_ADDR" => from }
    follow_redirect! if response.redirect?
    true
  end

  def toasts = shown_toasts.map { _1.at_css(".toast__message").text.squish }

  # Who made it doesn't matter here, only what the link does.
  def password_link_for(profile) = Profiles::PasswordLink.call(profile, by: profiles(:bob)).token

  def assert_signed_in = assert_select("form[action=?]", destroy_profile_session_path)
  def assert_signed_out = assert_select("form[action=?]", profile_session_path)
end
