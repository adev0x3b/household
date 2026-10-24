# frozen_string_literal: true

require "test_helper"

# The demo's door: on the demo installation (open accounts, DemoBuilders#on_the_demo)
# the sign-in page offers them and a press enters; elsewhere /demo sends the
# visitor to the demo installation, or is nothing.
class DemosControllerTest < ActionDispatch::IntegrationTest
  test "on the demo, the sign-in page is the door: each open account a button, and the banner on every page after" do
    demo_household
    on_the_demo do
      get demo_path
      assert_redirected_to new_profile_session_path

      get new_profile_session_path
      assert_response :success
      assert_select ".auth-card__title", text: I18n.t("demo.sign_in.title")
      assert_select ".auth-card__subtitle", text: I18n.t("demo.welcome")
      assert_select ".demo-personas form[action=?][method=post][data-turbo=false]", demo_path, 3
      assert_select ".demo-personas form input[name=as][value='sam.demo']"
      assert_select ".demo-personas button", text: I18n.t("demo.sign_in.enter_as", name: "Sam")
      assert_select "input[name='profile[login]']", 1, "the form stays, for an account of one's own"
      assert_select ".auth-card__link", { count: 0 }, "no link to another demo: this is it"
      assert_select ".account-menu__name", 0, "a GET signs nobody in: Turbo prefetches links, and any site can link here"

      post demo_path, params: { as: "alex.demo" }
      assert_redirected_to root_path
      assert_equal I18n.t("demo.welcome"), flash[:notice]

      follow_redirect!
      assert_response :success
      assert_select ".account-menu__name", text: "Alex"
      assert_select ".demo-banner form[data-turbo=false] .demo-banner__persona", 3
      assert_select ".demo-banner__persona.is-current", text: "Alex"
    end
  end

  test "the banner switches to another open account, and to nobody else" do
    demo_household
    on_the_demo do
      post demo_path, params: { as: "alex.demo" }
      follow_redirect! # the welcome, shown

      post demo_path, params: { as: "sam.demo" }
      assert_nil flash[:notice], "switching inside the demo needs no welcome"
      follow_redirect!
      assert_select ".account-menu__name", text: "Sam"

      post demo_path, params: { as: profiles(:alice).username } # a real account's username
      assert_response :not_found
      get root_path
      assert_select ".account-menu__name", text: "Sam"
    end
  end

  test "an open account that doesn't exist, or hasn't joined, is not a way in" do
    demo_household
    with_env("OPEN_ACCOUNTS" => "alex.demo,ghost.demo") do
      post demo_path, params: { as: "ghost.demo" }
      assert_response :not_found

      Profile.find_by!(username: "alex.demo").update_columns(invitation_token: "waiting")
      post demo_path, params: { as: "alex.demo" }
      assert_response :not_found
    end
  end

  test "an admin named as an open account is neither a button nor a way in" do
    demo_household.profiles.find_by!(username: "robin.demo").admin!
    on_the_demo do
      get new_profile_session_path
      assert_select ".demo-personas form", 2
      assert_select ".demo-personas form input[name=as][value='robin.demo']", 0

      post demo_path, params: { as: "robin.demo" }
      assert_response :not_found
      get root_path
      assert_redirected_to new_profile_session_path
    end
  end

  test "a stranger's wrong passwords never keep the next visitor out: the press unlocks the account" do
    alex = demo_household.profiles.find_by!(username: "alex.demo")
    Devise.maximum_attempts.times { alex.valid_for_authentication? { false } }
    assert_predicate alex.reload, :access_locked?, "locked like any account"

    on_the_demo do
      post demo_path, params: { as: "alex.demo" }
      assert_redirected_to root_path
      assert_not alex.reload.access_locked?
      follow_redirect!
      assert_select ".account-menu__name", text: "Alex"
    end
  end

  test "without open accounts there is no door: /demo goes to the demo installation, or nowhere" do
    demo_household
    get demo_path
    assert_response :not_found

    with_env("DEMO_HOST" => "demo.example.com") do
      get demo_path
      assert_redirected_to "#{Deployment.url(:demo)}/demo"
      get new_profile_session_path
      assert_select "a.auth-card__link[href=?]", Deployment.url(:demo), text: I18n.t("demo.sign_in_link")
    end

    get new_profile_session_path
    assert_select ".demo-personas", count: 0
    assert_select ".auth-card__link", count: 0
    assert_select ".auth-card__title", text: I18n.t("sessions.new.title")
    post demo_path, params: { as: "alex.demo" }
    assert_response :not_found

    sign_in profiles(:alice)
    get root_path
    assert_select ".demo-banner", count: 0
  end

  test "too many sign-in attempts are slowed down" do
    counting_rate_limits do
      10.times { post profile_session_path, params: { profile: { login: "nobody", password: "wrong" } } }
      assert_nil flash[:alert].to_s[I18n.t("rate_limit.exceeded")]

      post profile_session_path, params: { profile: { login: "nobody", password: "wrong" } }
    end

    assert_redirected_to new_profile_session_path
    assert_equal I18n.t("rate_limit.exceeded"), flash[:alert]
  end
end
