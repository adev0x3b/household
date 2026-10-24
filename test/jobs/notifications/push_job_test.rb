# frozen_string_literal: true

require "test_helper"

class Notifications::PushJobTest < ActiveJob::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @notification = Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: recipes(:roast_chicken), subject_title: "Sunday Roast Chicken")
    @subscription = push_subscription_for(@bob, origin: "https://household.example")
  end

  test "sends a declarative push in the recipient's language, linking back to where they subscribed" do
    @bob.update!(locale: "it")

    sent = capture_pushes { with_push_keys { Notifications::PushJob.perform_now(@notification, @subscription) } }

    assert_equal 1, sent.size
    push = sent.first
    assert_equal [ @subscription.endpoint, "p256dh", "auth", "normal", 1.day.to_i ], push.values_at(:endpoint, :p256dh, :auth, :urgency, :ttl)
    assert_equal PushBuilders::VAPID.public_key, push[:vapid][:public_key]

    message = JSON.parse(push[:message])
    assert_equal 8030, message["web_push"]
    assert_equal 1, message["app_badge"]
    routes = Rails.application.routes.url_helpers
    assert_equal({ "title" => "Alice ha condiviso una ricetta con te", "body" => "Sunday Roast Chicken", "lang" => "it",
                   "navigate" => "https://household.example#{routes.notification_path(@notification)}",
                   "data" => { "read" => "https://household.example#{routes.notification_read_receipt_path(@notification)}" } },
                 message["notification"].slice("title", "body", "lang", "navigate", "data"))
    assert @subscription.reload.last_succeeded_at
  end

  test "a device the push service no longer knows is forgotten" do
    with_push_keys do
      fail_push_with(WebPush::ExpiredSubscription) { Notifications::PushJob.perform_now(@notification, @subscription) }
    end

    assert_not PushSubscription.exists?(@subscription.id)
  end

  test "a busy push service, or one that can't be reached, is tried again later" do
    [ WebPush::PushServiceError, WebPush::TooManyRequests ].each do |busy|
      with_push_keys { fail_push_with(busy) { Notifications::PushJob.perform_now(@notification, @subscription) } }
    end
    [ Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError, EOFError ].each do |unreachable|
      with_push_keys { swapping(WebPush, :payload_send, ->(**) { raise unreachable }) { Notifications::PushJob.perform_now(@notification, @subscription) } }
    end

    assert PushSubscription.exists?(@subscription.id)
    assert_enqueued_jobs 5, only: Notifications::PushJob
  end

  test "a push the service refuses is reported and dropped, the notification kept under the bell" do
    [ WebPush::Unauthorized, WebPush::PayloadTooLarge, WebPush::ResponseError ].each do |refusal|
      assert_error_reported(refusal) do
        with_push_keys { fail_push_with(refusal) { Notifications::PushJob.perform_now(@notification, @subscription) } }
      end
    end

    assert PushSubscription.exists?(@subscription.id)
    assert_no_enqueued_jobs only: Notifications::PushJob
  end

  test "a device refused every push for a month is forgotten, unless the message was to blame" do
    @subscription.update_columns(created_at: 2.months.ago, last_succeeded_at: 31.days.ago)

    with_push_keys do
      fail_push_with(WebPush::PayloadTooLarge) { Notifications::PushJob.perform_now(@notification, @subscription) }
      assert PushSubscription.exists?(@subscription.id)

      fail_push_with(WebPush::Unauthorized) { Notifications::PushJob.perform_now(@notification, @subscription) }
      assert_not PushSubscription.exists?(@subscription.id)
    end
  end

  test "a device that never got a push counts its month from when it was turned on" do
    fresh = push_subscription_for(@bob)
    @subscription.update_columns(created_at: 31.days.ago)

    with_push_keys do
      [ @subscription, fresh ].each { |device| fail_push_with(WebPush::ResponseError) { Notifications::PushJob.perform_now(@notification, device) } }
    end

    assert_equal [ fresh ], PushSubscription.where(profile: @bob).to_a
  end

  test "nothing is sent without VAPID keys, or to a device that changed hands since" do
    sent = capture_pushes do
      Notifications::PushJob.perform_now(@notification, @subscription)
      @subscription.update!(profile: @alice)
      with_push_keys { Notifications::PushJob.perform_now(@notification, @subscription) }
    end

    assert_empty sent
  end

  private

  def capture_pushes
    sent = []
    swapping(WebPush, :payload_send, ->(**push) { sent << push }) { yield }
    sent
  end

  def fail_push_with(error, &)
    response = Struct.new(:code, :body).new("500", "")
    swapping(WebPush, :payload_send, ->(**) { raise error.new(response, "push.example.com") }, &)
  end
end
