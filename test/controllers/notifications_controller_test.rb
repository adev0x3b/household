# frozen_string_literal: true

require "test_helper"
class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
    @notification = Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: @recipe, subject_title: @recipe.name)
    sign_in @bob
  end

  test "the bell shows the unread count and loads its list when opened" do
    get root_path

    assert_select ".notifications__bell .notifications-badge:not([hidden])", text: "1"
    assert_select ".notifications__bell[aria-expanded=false][aria-controls=notifications-panel][data-dropdown-target=toggler]"
    assert_select "#notifications-panel"
    assert_select "turbo-frame#notifications-frame[loading=lazy][data-turbo-permanent][src='#{notifications_path}']"
    # Read again each time the bell opens, so rows say what is read now and how long ago.
    assert_select ".notifications[data-controller='dropdown bell'][data-action='dropdown:opened->bell#refresh']"
    assert_select "turbo-frame#notifications-frame[data-bell-target=list][refresh=morph]"
    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
  end

  test "the list holds your notifications only" do
    Notification.create!(profile: @alice, kind: :shared, subject: recipes(:pancakes), subject_title: "Not for Bob")

    get notifications_path, headers: { "Turbo-Frame" => Views::Notifications::List::FRAME_ID }

    assert_select "turbo-frame#notifications-frame #notifications-list .notifications__item", 1
    assert_select ".notifications__item.is-unread .notifications__item-title", text: "Alice shared a recipe with you"
    assert_select ".notifications__item-subject", text: "Sunday Roast Chicken"
    assert_select "#notifications-older", 0
  end

  test "the list lives in the bell: a visit of its own goes home" do
    get notifications_path

    assert_redirected_to root_path
  end

  test "older notifications come a page at a time, until the oldest" do
    older = Array.new(Notifications::BellPage::SIZE) do |age|
      Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: @recipe, created_at: (age + 1).days.ago)
    end

    get notifications_path, headers: { "Turbo-Frame" => Views::Notifications::List::FRAME_ID }
    assert_select "#notifications-list .notifications__item", Notifications::BellPage::SIZE
    assert_select "#notification_#{older.last.id}", 0
    assert_select "a#notifications-older[data-turbo-stream][href=?]", notifications_path(before: older[-2].id)

    get notifications_path(before: older[-2].id), as: :turbo_stream
    assert_select "turbo-stream[action=append][target=notifications-list] #notification_#{older.last.id}"
    assert_select "turbo-stream[action=replace][target=notifications-older] template", text: ""

    sign_in @alice
    get notifications_path(before: older.last.id), as: :turbo_stream
    assert_response :not_found
  end

  test "a push notification's link goes where it points and reads nothing" do
    get notification_path(@notification)

    assert_redirected_to recipe_path(@recipe)
    assert_predicate @notification.reload, :unread?
  end

  test "someone else's can't be followed from a link" do
    theirs = Notification.create!(profile: @alice, kind: :shared, subject: recipes(:pancakes))

    get notification_path(theirs)

    assert_response :not_found
  end
end
