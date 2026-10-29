# frozen_string_literal: true

require "test_helper"

# Changing one's password from the Account page: every other browser is
# signed out, this one stays, remembered if it was.
class AccountPasswordsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "alice's long password"
  NEW_PASSWORD = "alice's new long password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD, password_confirmation: PASSWORD) }
  end

  def change(current_password: PASSWORD, password: NEW_PASSWORD)
    patch account_password_path, params: { password_change: { current_password:, password:, password_confirmation: password } },
                                 headers: submitted_from(account_path)
  end

  test "the new password takes over; this browser stays signed in and the others are signed out" do
    elsewhere = open_session
    elsewhere.post profile_session_path, params: { profile: { login: "alice", password: PASSWORD } }
    elsewhere.get account_path
    assert_equal 200, elsewhere.response.status
    post profile_session_path, params: { profile: { login: "alice", password: PASSWORD } }

    change

    assert_redirected_to account_path
    assert @alice.reload.valid_password?(NEW_PASSWORD)
    follow_redirect!
    assert_response :success
    assert_toast "Your password has changed. Every other browser was signed out."
    elsewhere.get account_path
    assert_equal new_profile_session_url, elsewhere.response.location
  end

  test "a browser that was remembered still is" do
    post profile_session_path, params: { profile: { login: "alice", password: PASSWORD, remember_me: "1" } }
    remembered = cookies["remember_profile_token"]

    change

    assert_predicate cookies["remember_profile_token"], :present?
    assert_not_equal remembered, cookies["remember_profile_token"], "the old cookie named the old password"
  end

  test "push stays on for this browser alone" do
    sign_in @alice
    elsewhere = push_subscription_for(@alice)
    with_push_keys { post push_subscription_path, params: { subscription: browser_subscription("https://push.example.com/send/here") }, as: :json }

    change

    assert_equal [ "https://push.example.com/send/here" ], @alice.push_subscriptions.pluck(:endpoint)
    assert_not PushSubscription.exists?(elsewhere.id)
  end

  test "a wrong password in use draws the page again and changes nothing" do
    sign_in @alice
    change(current_password: "a guess")

    assert_response :unprocessable_content
    assert_form_error "Your password is wrong"
    assert @alice.reload.valid_password?(PASSWORD)
  end
end
