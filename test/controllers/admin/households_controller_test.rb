# frozen_string_literal: true

require "test_helper"

class Admin::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
    sign_in @admin
  end

  test "the admin sees every household with how full it is" do
    get admin_households_path

    assert_response :success
    assert_select ".household__row", Household.count
    assert_select "a[href=?]", admin_household_path(households(:elsewhere)), text: /Elsewhere/
    assert_match(/3 members/, response.body)
  end

  test "creating a household invites its first member and opens its page with their link" do
    Platform::Setting.create!(invitations_per_member: 5)
    get new_admin_household_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='household[first_member_email]']", admin_households_path
    assert_select "label[for=household_name] + * input#household_name[required][autocomplete=off]"
    assert_select "input#household_first_member_email[type=email][required]"
    assert_select "input#household_first_member_first_name:not([required])"

    assert_difference -> { Household.count }, 1 do
      post admin_households_path, params: { household: { name: "Casa Verdi", first_member_email: "anna@example.com", first_member_first_name: "Anna" } }
    end

    household = Household.find_by!(name: "Casa Verdi")
    assert_redirected_to admin_household_path(household)
    follow_redirect!
    assert_select ".household__row--invited .household__name", text: "anna@example.com"
    token = response.body[/invitation_token=([\w-]+)/, 1]
    assert_equal household.invitations.sole, Profile.find_by_invitation_token(token, true)
    assert_equal 5, households(:example).invites_left_for(@admin), "the admin's own invitations are untouched"

    get admin_household_path(household)
    assert_no_match(/invitation_token=/, response.body)
  end

  test "a household that can't invite its first member isn't created" do
    assert_no_difference -> { Household.count } do
      post admin_households_path, params: { household: { name: "Casa Verdi", first_member_email: profiles(:bob).email } }, as: :turbo_stream
    end

    assert_select "turbo-stream[target=modals] form"
  end

  test "the admin can invite into any household from its page" do
    get admin_household_path(households(:elsewhere))
    assert_select "a[href=?]", new_household_invitation_path(households(:elsewhere))

    assert_difference -> { households(:elsewhere).invitations.count }, 1 do
      post household_invitations_path(households(:elsewhere)), params: { profile: { email: "erin@example.com" } }, as: :turbo_stream
    end
  end

  test "members have none of this" do
    sign_in profiles(:bob)

    get admin_households_path
    assert_response :redirect
    get admin_household_path(households(:elsewhere))
    assert_response :redirect
    assert_no_difference -> { Household.count } do
      post admin_households_path, params: { household: { name: "Mine", first_member_email: "x@example.com" } }
    end
    get root_path
    assert_select "a[href=?]", admin_households_path, count: 0
    assert_select "a[href=?]", household_path
  end
end
