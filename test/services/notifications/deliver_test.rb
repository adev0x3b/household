# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class Notifications::DeliverTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
  end

  test "saves the notification and pushes the count, its row and a toast to the recipient" do
    streams = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
      notification = Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)

      assert_equal [ @bob, @alice, @recipe, "Sunday Roast Chicken" ],
                   [ notification.profile, notification.actor, notification.subject, notification.subject_title ]
    end

    assert_equal([ %w[replace .notifications-badge], %w[prepend notifications-list], %w[append toast-container] ],
                 streams.map { [ _1["action"], _1["target"] || _1["targets"] ] })
    assert_includes streams.first.to_html, ">1<"
    assert_includes streams.second.to_html, "Alice shared a recipe with you"
    assert_includes streams.third.to_html, "Sunday Roast Chicken"
  end

  test "speaks the recipient's language, not the sender's" do
    @bob.update!(locale: "it")

    streams = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
      Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
    end

    assert_includes streams.second.to_html, "Alice ha condiviso una ricetta con te"
  end

  test "a name can't inject markup into the toast" do
    @recipe.update!(name: "<img src=x onerror=alert(1)>")

    streams = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
      Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
    end

    assert_not_includes streams.third.to_html, "<img"
  end

  test "nobody is notified of what they did themselves" do
    assert_no_difference "Notification.count" do
      assert_nil Notifications::Deliver.call(recipient: @alice, kind: :shared, subject: @recipe, actor: @alice)
    end
    assert_no_turbo_stream_broadcasts [ @alice, :notifications ]
  end

  test "a series is called by its label" do
    notification = Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: events(:groceries),
                                               actor: @alice)

    assert_equal events(:groceries).event_label, notification.subject_title
  end

  test "a job's end has no actor, a colored toast, and a detail cut to one line" do
    streams = capture_turbo_stream_broadcasts([ @alice, :notifications ]) do
      notification = Notifications::Deliver.call(recipient: @alice, kind: :eval_cases_failed,
                                                 data: { language: "Italian", detail: "the model\ndidn't answer " + ("x" * 300) })

      assert_nil notification.actor
      assert_operator notification.data["detail"].length, :<=, Notifications::Deliver::DETAIL_LENGTH
      assert_not_includes notification.data["detail"], "\n"
    end

    assert_includes streams.third.to_html, "toast--alert"
    assert_includes streams.third.to_html, "The Italian test cases couldn't be written"
  end

  test "each of the recipient's devices gets the notification as a push, once push is set up" do
    phone = push_subscription_for(@bob)
    laptop = push_subscription_for(@bob)
    push_subscription_for(@alice)

    assert_no_enqueued_jobs only: Notifications::PushJob do
      Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
    end

    with_push_keys do
      notification = nil
      assert_enqueued_jobs 2, only: Notifications::PushJob do
        notification = Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
      end
      assert_enqueued_with job: Notifications::PushJob, args: [ notification, phone ]
      assert_enqueued_with job: Notifications::PushJob, args: [ notification, laptop ]
    end
  end

  test "the recipient hears of it once it is saved, and never of one rolled back" do
    push_subscription_for(@bob)

    with_push_keys do
      assert_no_difference "Notification.count" do
        assert_no_enqueued_jobs only: Notifications::PushJob do
          assert_no_turbo_stream_broadcasts [ @bob, :notifications ] do
            Notification.transaction do
              Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
              raise ActiveRecord::Rollback
            end
          end
        end
      end

      streams = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
        Notification.transaction do
          Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: @recipe, actor: @alice)
          assert_no_enqueued_jobs only: Notifications::PushJob
        end
      end
      assert_equal 3, streams.size
      assert_enqueued_jobs 1, only: Notifications::PushJob
    end
  end
end
