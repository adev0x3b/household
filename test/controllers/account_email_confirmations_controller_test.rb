# frozen_string_literal: true

require "test_helper"

# The page a link to confirm an address opens: it changes nothing until
# its form is sent with the password in use, signed in as the person it
# was mailed to.
class AccountEmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice)
    @alice.update!(password: PASSWORD, password_confirmation: PASSWORD)
    @alice.update!(unconfirmed_email: "alice@new.example")
    @token = @alice.email_confirmation_token!
  end

  test "opening the link shows the address and a form that asks for the password, and confirms nothing" do
    sign_in @alice
    get account_email_confirmation_path(token: @token)

    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"], "no other site learns the link"
    assert_select ".panel__title", text: "alice@new.example"
    assert_select "form[action=?]", account_email_confirmation_path do
      assert_select "input[type=hidden][name=?][value=?]", "email_confirmation[token]", @token
      assert_select "input[type=password][name=?][autocomplete=current-password]", "email_confirmation[current_password]"
    end
    assert_equal "alice@new.example", @alice.reload.unconfirmed_email
  end

  test "its form, sent with the password, confirms, and the account page says so" do
    sign_in @alice
    confirm(password: PASSWORD)

    assert_redirected_to account_path
    assert_equal "alice@new.example", @alice.reload.email
    assert_predicate @alice, :email_confirmed?
    follow_redirect!
    assert_toast "alice@new.example is confirmed."
  end

  test "a session alone confirms nothing: without the password the page asks again, the link still in it" do
    sign_in @alice
    confirm(password: "not the password")

    assert_response :unprocessable_content
    assert_select ".panel__title", text: "alice@new.example"
    assert_select "input[type=hidden][name=?][value=?]", "email_confirmation[token]", @token
    assert_form_error "Your password is wrong"
    assert_select "input[name=?][aria-invalid=true]", "email_confirmation[current_password]"
    assert_equal "alice@new.example", @alice.reload.unconfirmed_email
    assert_not @alice.email_confirmed?
  end

  test "signed out, the link asks to sign in first and comes back to it" do
    get account_email_confirmation_path(token: @token)
    assert_redirected_to new_profile_session_path

    sign_in @alice
    get new_profile_session_path
    assert_redirected_to account_email_confirmation_path(token: @token)
  end

  test "someone else's link, or one out of date, says why and offers nothing to send" do
    sign_in profiles(:bob)
    get account_email_confirmation_path(token: @token)
    assert_select ".panel p", text: /mailed to someone else/
    assert_select "form[action=?]", account_email_confirmation_path, count: 0

    confirm(password: PASSWORD)
    assert_response :unprocessable_content
    assert_toast "It was mailed to someone else."
    assert_equal "alice@new.example", @alice.reload.unconfirmed_email

    get account_email_confirmation_path(token: "not-a-token")
    assert_select ".panel p", text: /It has expired/
  end

  private

  def confirm(password:)
    post account_email_confirmation_path, params: { email_confirmation: { token: @token, current_password: password } },
                                          headers: submitted_from(account_email_confirmation_path)
  end
end
