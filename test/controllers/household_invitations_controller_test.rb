# frozen_string_literal: true

require "test_helper"

class HouseholdInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  def invite(email, household: households(:example))
    post household_invitations_path(household), params: { profile: { email: email, first_name: "Erin" } }, as: :turbo_stream
  end

  test "the household page lists its members, not another household's, and offers to invite" do
    get household_path

    assert_response :success
    assert_select "#household-people .household__row", 3
    assert_select ".household__name", text: /Alice Example/
    assert_no_match(/Dave/, response.body)
    assert_select "a[href=?]", new_household_invitation_path(households(:example))
  end

  test "inviting adds them to the page with the link to accept, shown once" do
    assert_difference -> { households(:example).invitations.count }, 1 do
      invite("erin@example.com")
    end

    assert_response :success
    assert_select ".household__row--invited .household__name", text: "erin@example.com"
    token = response.body[/invitation_token=([\w-]+)/, 1]
    assert_equal Profile.find_by!(email: "erin@example.com"), Profile.find_by_invitation_token(token, true)

    get household_path
    assert_select ".household__row--invited", 1
    assert_no_match(/invitation_token=/, response.body)
  end

  test "an invitation that can't be made re-renders the form with why" do
    assert_no_difference -> { Profile.count } do
      invite(profiles(:outsider).email)
    end

    assert_select "turbo-stream[target=modals] form"
    assert_match(/has already been taken/, response.body)
  end

  test "an invitation can be renewed and cancelled from its row" do
    invite("erin@example.com")
    invitation = Profile.find_by!(email: "erin@example.com")
    old_token = response.body[/invitation_token=([\w-]+)/, 1]

    post household_invitation_renewals_path(invitation), as: :turbo_stream
    assert_response :success
    assert_not_equal old_token, response.body[/invitation_token=([\w-]+)/, 1]

    delete household_invitation_path(invitation), as: :turbo_stream
    assert_response :success
    assert_not Profile.exists?(invitation.id)
    assert_select ".household__row--invited", 0
  end

  test "a member is never renewed or cancelled as if they were an invitation" do
    delete household_invitation_path(profiles(:bob)), as: :turbo_stream

    assert_response :not_found
    assert Profile.exists?(profiles(:bob).id)
  end

  test "another household's invitations are out of reach, as if they weren't there" do
    theirs = Households::Invite.call(households(:elsewhere), inviter: profiles(:outsider), email: "erin@example.com").profile
    get household_path # a 404 first would drop the test sign-in before its session is saved

    assert_no_difference -> { Profile.count } do
      invite("frank@example.com", household: households(:elsewhere))
      assert_response :not_found
      delete household_invitation_path(theirs), as: :turbo_stream
      assert_response :not_found
      post household_invitation_renewals_path(theirs), as: :turbo_stream
      assert_response :not_found
    end
    get new_household_invitation_path(households(:elsewhere)), as: :turbo_stream
    assert_response :not_found
  end

  test "accepting the link asks for a username and a password, and signs them in as a member, with a member's start" do
    invite("erin@example.com")
    token = response.body[/invitation_token=([\w-]+)/, 1]
    sign_out :profile

    get accept_profile_invitation_path(invitation_token: token)
    assert_response :success
    assert_select "input[name='profile[username]']"
    assert_match(/Example/, response.body)

    put profile_invitation_path, params: { profile: { invitation_token: token, username: "", password: "a-long-password", password_confirmation: "a-long-password" } }
    assert_response :unprocessable_content
    assert_select "input[name='profile[invitation_token]'][value=?]", token
    invited = Profile.find_by!(email: "erin@example.com")
    assert_empty invited.analytes, "a refused acceptance leaves the invitation as it was"
    assert_not conversations(:example_chat).participant?(invited)

    put profile_invitation_path, params: { profile: { invitation_token: token, username: "erin", first_name: "Erin", password: "a-long-password", password_confirmation: "a-long-password" } }
    assert_redirected_to root_path
    erin = Profile.find_by!(username: "erin")
    assert_equal [ households(:example), false ], [ erin.household, erin.invitation_pending? ]
    assert_equal Analyte::STANDARD_NAMES.sort, erin.analytes.pluck(:name).sort
    assert conversations(:example_chat).reload.participant?(erin)

    get household_path
    assert_select ".household__row", 4
  end

  test "there is no sign-up, and devise's own invite form is gone" do
    sign_out :profile

    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("#{Rails.configuration.x.mount_path}/profiles/sign_up") }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("#{Rails.configuration.x.mount_path}/profiles/invitation/new") }
    get new_profile_session_path
    assert_no_match(/sign_up/, response.body)
  end
end
