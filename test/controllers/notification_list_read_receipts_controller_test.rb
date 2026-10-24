# frozen_string_literal: true

require "test_helper"

class NotificationListReadReceiptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @notification = Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: recipes(:roast_chicken), subject_title: "Roast")
    sign_in @bob
  end

  test "the bell offers to mark all read" do
    get root_path

    assert_select ".notifications__header form[action=?][method=post] button.notifications__read-all", notification_list_read_receipt_path
  end

  test "mark all read clears the count and yours only" do
    theirs = Notification.create!(profile: @alice, kind: :shared, subject: recipes(:pancakes))

    post notification_list_read_receipt_path, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][targets='.notifications-badge']"
    assert_select "turbo-stream[action=replace][target=notifications-frame]"
    assert_not @notification.reload.unread?
    assert_predicate theirs.reload, :unread?
  end
end
