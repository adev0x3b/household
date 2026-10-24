# frozen_string_literal: true

require "test_helper"

class LinkAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @alice
  end

  test "accepting from the bell" do
    link = Link.create!(requester: @bob, addressee: @alice)

    post link_acceptance_path(link), as: :turbo_stream
    assert_predicate link.reload, :accepted?
  end
  test "only the one asked accepts" do
    link = Link.create!(requester: @alice, addressee: @bob)

    post link_acceptance_path(link), as: :turbo_stream
    assert_predicate link.reload, :pending?
  end
  test "without Turbo, a change comes back to the page with its toast" do
    post link_acceptance_path(Link.create!(requester: @bob, addressee: @alice))

    assert_redirected_to links_path
    assert_equal I18n.t("links.notices.accepted", name: @bob.display_name), flash[:success]
  end

  test "someone else's link is not found" do
    link = Link.create!(requester: @bob, addressee: profiles(:carol))

    post link_acceptance_path(link), as: :turbo_stream
    assert_response :not_found
  end
end
