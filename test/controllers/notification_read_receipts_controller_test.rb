# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class NotificationReadReceiptsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
    @notification = Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: @recipe, subject_title: @recipe.name)
    sign_in @bob
  end

  test "reading one updates the count elsewhere and goes to what it's about" do
    assert_turbo_stream_broadcasts([ @bob, :notifications ], count: 1) do
      post notification_read_receipt_path(@notification)
    end

    assert_redirected_to recipe_path(@recipe)
    assert_response :see_other
    assert_not @notification.reload.unread?
  end

  test "one with nowhere to go sends you back" do
    @notification.update!(kind: :unshared)

    post notification_read_receipt_path(@notification), headers: { "HTTP_REFERER" => calendar_url }

    assert_redirected_to calendar_url
    assert_not @notification.reload.unread?
  end

  test "someone else's can't be read" do
    theirs = Notification.create!(profile: @alice, kind: :shared, subject: recipes(:pancakes))

    post notification_read_receipt_path(theirs)

    assert_response :not_found
    assert_predicate theirs.reload, :unread?
  end

  test "the service worker reads a tapped one without the page's token, and nothing else goes without it" do
    with_forgery_protection do
      post notification_read_receipt_path(@notification)
      assert_redirected_to recipe_path(@recipe)

      post notification_list_read_receipt_path, as: :turbo_stream
      assert_response :unprocessable_content
    end

    assert_not @notification.reload.unread?
  end

  private

  # The test environment turns CSRF protection off; this test is about
  # where it stays off in production.
  def with_forgery_protection
    protecting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = protecting
  end
end
