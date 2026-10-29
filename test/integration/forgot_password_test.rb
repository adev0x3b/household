# frozen_string_literal: true

require "test_helper"

# "Forgot your password?", asked without signing in where the installation
# mails: the page answers the same whoever was asked for, only a job hears
# who it was, by id, and a mailed link works once, for half an hour.
class ForgotPasswordTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD, email_confirmed_at: 1.day.ago) }
  end

  test "where the installation mails, the sign-in page links to it and keeps the way that needs no mail" do
    with_relay { get new_profile_session_path }

    assert_select "a.auth-card__link[href=?]", new_profile_password_path, text: I18n.t("sessions.new.forgot_link")
    assert_select ".auth-card__note", text: I18n.t("sessions.new.forgot_owner")

    with_relay { get new_profile_password_path }
    assert_response :success
    assert_select "title", text: /\A#{Regexp.escape(I18n.t("passwords.new.title"))}/
    assert_select "form[action=?][method=post] input[name='profile[login]'][autocomplete=username][required]", profile_password_path
  end

  test "answers the same whoever is asked for, and hands the job an id, never what was typed" do
    { @alice.username => @alice.id, " #{@alice.email.upcase} " => @alice.id, "nobody" => nil, "" => nil }.each do |login, id|
      assert_enqueued_with(job: Profiles::PasswordLinkRequestJob, args: [ id ]) do
        with_relay { post profile_password_path, params: { profile: { login: login } } }
      end

      assert_redirected_to new_profile_session_path
      assert_equal I18n.t("passwords.notices.asked", minutes: 30), flash[:notice]
    end
  end

  test "a request its forms never send is refused as malformed, and asks for nothing" do
    [ { profile: "alice" }, { profile: [ "alice" ] }, {} ].each do |params|
      assert_no_error_reported { with_relay { post profile_password_path, params: params } }
      assert_response :bad_request

      assert_no_error_reported { put profile_password_path, params: params }
      assert_response :bad_request
    end
    assert_no_enqueued_jobs only: Profiles::PasswordLinkRequestJob
  end

  test "no such page where nothing is mailed, nor for someone signed in" do
    get new_profile_password_path
    assert_response :not_found
    post profile_password_path, params: { profile: { login: @alice.username } }
    assert_response :not_found
    assert_no_enqueued_jobs only: Profiles::PasswordLinkRequestJob

    sign_in @alice
    with_relay { get new_profile_password_path }
    assert_redirected_to root_path
  end

  test "five asks an hour from one address; a link's own limit is counted apart" do
    counting_rate_limits do
      with_relay do
        5.times { post profile_password_path, params: { profile: { login: "nobody" } } }
        assert_redirected_to new_profile_session_path

        post profile_password_path, params: { profile: { login: "nobody" } }
        assert_redirected_to new_profile_password_path
        assert_equal I18n.t("rate_limit.exceeded"), flash[:alert]

        put profile_password_path, params: { profile: { reset_password_token: "guess", password: PASSWORD, password_confirmation: PASSWORD } }
        assert_response :unprocessable_content
      end
    end
  end

  test "a mailed link sets the password within half an hour, once, and opens a locked account" do
    @alice.lock_access!
    token = @alice.short_password_link_token!

    get edit_profile_password_path(reset_password_token: token)
    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"], "no other site learns the link"
    put profile_password_path, params: { profile: { reset_password_token: token, password: "another-long-one", password_confirmation: "another-long-one" } }

    @alice.reload
    assert @alice.valid_password?("another-long-one")
    assert_not @alice.access_locked?
    assert_nil Profile.with_reset_password_token(token), "once"
  end

  test "a mailed link half an hour old sets nothing" do
    token = @alice.short_password_link_token!
    travel Profile::SHORT_PASSWORD_LINK_FOR + 1.second

    put profile_password_path, params: { profile: { reset_password_token: token, password: "another-long-one", password_confirmation: "another-long-one" } }

    assert_response :unprocessable_content
    assert_not @alice.reload.valid_password?("another-long-one")
  end
end
