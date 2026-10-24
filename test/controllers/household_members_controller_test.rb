# frozen_string_literal: true

require "test_helper"

class HouseholdMembersControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password"

  setup do
    @owner = profiles(:alice)
    @member = profiles(:bob)
  end

  test "the owner removes a member with everything they kept, and is offered no button on themselves" do
    sign_in @owner
    get household_path
    assert_select "a[href=?]", household_member_path(@member)
    assert_select "a[href=?]", household_member_path(@owner), count: 0
    assert_select ".household__name", text: /Alice Example\s*owner/

    transfer = transfer!(payer: @owner, counterparty: @member, date: Date.current, cents: 1000)
    delete household_member_path(@member), as: :turbo_stream

    assert_response :success
    assert_not Profile.exists?(@member.id)
    assert_empty Event.where(profile_id: @member.id)
    assert_nil transfer.event.details.reload.counterparty_profile_id
    assert_select ".household__row", 2
  end

  test "a member's name is text in the owner's toast, never markup" do
    @member.update!(first_name: "<img src=x onerror=alert(1)>")
    sign_in @owner

    delete household_member_path(@member), as: :turbo_stream

    assert_response :success
    assert_no_injected_markup
    assert_toast "<img src=x onerror=alert(1)> removed"
  end

  test "a member removes nobody; the admin removes anyone, in any household" do
    sign_in @member
    get household_path
    assert_select "a[href*=?]", "household_members", count: 0
    delete household_member_path(profiles(:carol)), as: :turbo_stream
    assert_response :forbidden
    assert Profile.exists?(profiles(:carol).id)

    sign_in admin
    delete household_member_path(profiles(:outsider)), params: { password: PASSWORD }, as: :turbo_stream
    assert_response :success
    assert_not Profile.exists?(profiles(:outsider).id)
    assert_nil households(:elsewhere).reload.owner
  end

  test "the admin types their password before removing someone; a wrong one removes nobody and counts" do
    sign_in admin
    outsider = profiles(:outsider)

    delete household_member_path(outsider), as: :turbo_stream
    assert_response :success
    assert Profile.exists?(outsider.id)
    assert_select "turbo-stream[action=update][target=modals]" do
      assert_select ".modal__subtitle", text: "Remove #{outsider.display_name} from the household"
      assert_select "form[action=?]", household_member_path(outsider) do
        assert_select "input[name=_method][value=delete]", visible: false
        assert_select "input[name=password][type=password][autocomplete=current-password]"
        assert_select "button.modal__btn--danger", text: "Remove"
      end
    end

    delete household_member_path(outsider), params: { password: "not it" }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /isn't your password/
    assert Profile.exists?(outsider.id)
    assert_equal 1, @owner.reload.failed_attempts

    delete household_member_path(outsider), params: { password: PASSWORD }, as: :turbo_stream
    assert_response :success
    assert_not Profile.exists?(outsider.id)
    assert_select "turbo-stream[action=update][target=modals]", text: ""

    delete household_member_path(profiles(:carol)), as: :turbo_stream
    assert_not Profile.exists?(profiles(:carol).id), "the password holds a while"
  end

  test "the new-link button shows to the inviter and the admin, cancelling to the owner too" do
    sign_in @member
    post household_invitations_path(households(:example)), params: { profile: { email: "erin@example.com" } }, as: :turbo_stream
    invitation = Profile.find_by!(email: "erin@example.com")
    get household_path
    assert_select "a[href=?]", household_invitation_renewals_path(invitation)
    assert_select "a[href=?]", household_invitation_path(invitation)

    sign_in @owner
    get household_path
    assert_select "a[href=?]", household_invitation_renewals_path(invitation), count: 0
    assert_select "a[href=?]", household_invitation_path(invitation)
    post household_invitation_renewals_path(invitation), as: :turbo_stream
    assert_response :forbidden

    sign_in profiles(:carol)
    get household_path
    assert_select "a[href=?]", household_invitation_path(invitation), count: 0
    delete household_invitation_path(invitation), as: :turbo_stream
    assert_response :forbidden
    assert Profile.exists?(invitation.id)

    sign_in(profiles(:carol).tap { _1.update!(role: :admin) })
    get household_path
    assert_select "a[href=?]", household_invitation_renewals_path(invitation)
  end

  test "the admin or the owner make a member a link to set a password, which works once" do
    sign_in @owner
    get household_path
    assert_select "a[href=?]", household_member_password_links_path(@member)
    assert_select "a[href=?]", household_member_password_links_path(@owner), count: 0

    post household_member_password_links_path(@member), as: :turbo_stream
    assert_response :success
    token = response.body[/reset_password_token=([\w-]+)/, 1]
    assert_predicate token, :present?
    assert_match "Bob", response.body[/household__link-hint[^<]*>([^<]*)/, 1]

    sign_out :profile
    get edit_profile_password_path(reset_password_token: token)
    assert_response :success
    assert_select "input[name='profile[password]']"

    put profile_password_path, params: { profile: { reset_password_token: token, password: "short", password_confirmation: "short" } }
    assert_response :unprocessable_content

    put profile_password_path, params: { profile: { reset_password_token: token, password: "a-brand-new-password", password_confirmation: "a-brand-new-password" } }
    assert_response :redirect
    assert @member.reload.valid_password?("a-brand-new-password")
    assert_nil @member.reset_password_token

    sign_in profiles(:carol)
    post household_member_password_links_path(@member), as: :turbo_stream
    assert_response :forbidden, "a plain member makes no links"
  end

  test "the admin types their password before making someone a link to set theirs" do
    sign_in admin
    outsider = profiles(:outsider)

    post household_member_password_links_path(outsider), as: :turbo_stream
    assert_response :success
    assert_nil outsider.reload.reset_password_token
    assert_select ".modal__subtitle", text: "A link for #{outsider.display_name} to set a password"
    assert_select "form[action=?] input[name=password]", household_member_password_links_path(outsider)

    post household_member_password_links_path(outsider), params: { password: "" }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_nil outsider.reload.reset_password_token

    post household_member_password_links_path(outsider), params: { password: PASSWORD }, as: :turbo_stream
    assert_response :success
    assert_predicate outsider.reload.reset_password_token, :present?
    assert_match(/reset_password_token=[\w-]+/, response.body)
  end

  test "who invited a housemate makes no link to set their password, then or later" do
    carol = profiles(:carol)
    invitation = Households::Invite.call(households(:example), inviter: carol, email: "erin@example.com", first_name: "Erin")
    erin = Profile.accept_invitation!(invitation_token: invitation.token, username: "erin",
                                      password: "a long secret phrase", password_confirmation: "a long secret phrase")
    assert_empty erin.errors

    sign_in carol
    get household_path
    assert_select "a[href=?]", household_member_password_links_path(erin), count: 0
    post household_member_password_links_path(erin), as: :turbo_stream
    assert_response :forbidden

    sign_out :profile
    travel 90.days
    sign_in carol
    get household_path
    post household_member_password_links_path(erin), as: :turbo_stream
    assert_response :forbidden
    assert_nil erin.reload.reset_password_token
    assert erin.valid_password?("a long secret phrase")
  end

  private

  def admin = @owner.tap { _1.update!(role: :admin, password: PASSWORD, password_confirmation: PASSWORD) }
end
