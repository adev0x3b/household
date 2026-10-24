# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @alice
  end

  test "the navbar's Links button counts what waits for an answer" do
    Link.create!(requester: @bob, addressee: @alice)

    get root_path
    assert_select "a.navbar-link[href='#{links_path}'] .links-badge:not([hidden]) [aria-hidden]", text: "1"
  end

  test "the page offers to link with each housemate" do
    get links_path

    assert_response :success
    assert_select "#links-page"
    assert_select "a[data-turbo-method=post][href=?]", links_path(profile_id: @bob.id)
    assert_select "a[href=?]", links_path(profile_id: profiles(:outsider).id), 0
  end

  test "asking to link tells the other, who can accept from the bell" do
    assert_difference [ -> { Link.count }, -> { @bob.notifications.count } ], 1 do
      post links_path(profile_id: @bob.id), as: :turbo_stream
    end

    link = Link.last
    assert_predicate link, :pending?
    notification = @bob.notifications.last
    assert_equal "Alice wants to link with you", wording_of(notification).title
    assert_equal [ :accept, :decline ], Notifications::Destination.new(notification).actions.map(&:name)
    assert_includes response.body, %(target="links-page")
  end

  test "a housemate's name is text in the toast, never markup" do
    @bob.update!(first_name: "<img src=x onerror=alert(1)>")

    post links_path(profile_id: @bob.id), as: :turbo_stream

    assert_no_injected_markup
    assert_toast "Invited <img src=x onerror=alert(1)> to link"
  end

  test "nobody outside the household" do
    post links_path(profile_id: profiles(:outsider).id), as: :turbo_stream
    assert_response :not_found
  end

  test "nobody twice" do
    Link.create!(requester: @alice, addressee: @bob)
    assert_no_difference "Link.count" do
      post links_path(profile_id: @bob.id), as: :turbo_stream
    end
    assert_response :forbidden
  end

  test "asking someone who already asked accepts theirs" do
    link = Link.create!(requester: @bob, addressee: @alice)

    assert_no_difference "Link.count" do
      post links_path(profile_id: @bob.id), as: :turbo_stream
    end
    assert_predicate link.reload, :accepted?
    assert_equal LinkGrant::TYPES.size * 2, link.link_grants.count
    assert_equal "Alice accepted your invitation to link", wording_of(@bob.notifications.last).title
  end

  test "declining drops the link and tells the asker; taking it back tells nobody" do
    link = Link.create!(requester: @bob, addressee: @alice)
    delete link_path(link), as: :turbo_stream
    assert_not Link.exists?(link.id)
    assert_equal "Alice declined your invitation to link", wording_of(@bob.notifications.last).title

    link = Link.create!(requester: @alice, addressee: @bob)
    assert_no_difference "Notification.count" do
      delete link_path(link), as: :turbo_stream
    end
    assert_not Link.exists?(link.id)
  end

  test "unlinking ends the grants and the requests waiting on it" do
    link = link!(@alice, @bob)

    delete link_path(link), as: :turbo_stream
    assert_not Link.exists?(link.id)
    assert_equal 0, LinkGrant.where(link_id: link.id).count
    assert_equal "Alice unlinked from you", wording_of(@bob.notifications.last).title
    assert_not Event.accessible_by(@bob).exists?(events(:groceries).id)
  end

  test "someone else's link is not found" do
    link = Link.create!(requester: @bob, addressee: profiles(:carol))

    delete link_path(link), as: :turbo_stream
    assert_response :not_found
  end

  test "a pill sets what the partner may do, and they hear about it once while unread" do
    link = link!(@alice, @bob)
    grant = LinkGrant.find_by!(grantor: @alice, grantee: @bob, event_type: "Task")

    get links_path
    assert_select "#link-#{link.id} a[data-turbo-method=patch][href=?]", link_grant_path(link, "Task", permission: "write", level: "on")

    patch link_grant_path(link, "Task", permission: "write", level: "on"), as: :turbo_stream
    patch link_grant_path(link, "Task", permission: "delete", level: "off"), as: :turbo_stream

    assert_equal(%i[on on ask off], LinkGrant::ACTIONS.map { grant.reload.level(_1) })
    assert_equal 1, @bob.notifications.link_permissions_changed.count
  end

  # A kind added to the app after the link was accepted has no row: it is
  # shown off, the partner sees nothing of it, and the first tap saves it.
  test "a kind with no grant yet is off until its owner turns it on" do
    link = link!(@alice, @bob)
    LinkGrant.where(link: link, event_type: "Task").delete_all

    get links_path
    assert_select "#link-#{link.id} a[data-turbo-method=patch][href=?]", link_grant_path(link, "Task", permission: "read", level: "on")
    assert_not Event.accessible_by(@bob).exists?(events(:groceries).id)

    assert_difference "LinkGrant.count", 1 do
      patch link_grant_path(link, "Task", permission: "read", level: "on"), as: :turbo_stream
    end
    assert_response :success
    grant = LinkGrant.find_by!(grantor: @alice, grantee: @bob, event_type: "Task")
    assert_equal(%i[on off off off], LinkGrant::ACTIONS.map { grant.level(_1) })
    assert Event.accessible_by(@bob).exists?(events(:groceries).id)
    assert_not LinkGrant.exists?(grantor: @bob, grantee: @alice, event_type: "Task"), "Bob's own kind stays unset"
  end

  test "a tap sets what the viewer gives, never what the partner gives" do
    link = link!(@alice, @bob)
    theirs = LinkGrant.find_by!(grantor: @bob, grantee: @alice, event_type: "Task")

    patch link_grant_path(link, "Task", permission: "write", level: "on"), as: :turbo_stream
    assert_predicate theirs.reload, :write_ask?
  end

  test "a link one isn't in has no grants to set" do
    link = link!(@bob, profiles(:carol))

    patch link_grant_path(link, "Task", permission: "read", level: "off"), as: :turbo_stream
    assert_response :not_found
    assert_predicate LinkGrant.find_by!(grantor: @bob, grantee: profiles(:carol), event_type: "Task"), :read_on?
  end

  test "a link not accepted yet has no grants to set" do
    pending = Link.create!(requester: @alice, addressee: @bob)

    assert_no_difference "LinkGrant.count" do
      patch link_grant_path(pending, "Task", permission: "read", level: "on"), as: :turbo_stream
    end
    assert_response :not_found
  end

  test "only kinds of series are granted" do
    link = link!(@alice, @bob)

    patch link_grant_path(link, "Profile", permission: "read", level: "on"), as: :turbo_stream
    assert_response :not_found
  end

  test "read has no ask" do
    link = link!(@alice, @bob)

    patch link_grant_path(link, "Task", permission: "read", level: "ask"), as: :turbo_stream
    assert_response :unprocessable_content
    assert_toast I18n.t("refusals.unknown_choice")
  end
end
