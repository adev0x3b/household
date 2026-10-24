# frozen_string_literal: true

require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @bob
  end

  test "turning notifications on saves this device for whoever is signed in, where it subscribed" do
    with_push_keys do
      assert_difference -> { @bob.push_subscriptions.count } do
        post push_subscription_path, params: { subscription: browser_subscription("https://push.example.com/send/bob") }, as: :json
      end
    end

    assert_response :created
    subscription = @bob.push_subscriptions.last
    assert_equal [ "https://push.example.com/send/bob", "http://www.example.com" ], [ subscription.endpoint, subscription.origin ]
  end

  test "the same browser subscribed by someone else is theirs from then on" do
    shared_phone = browser_subscription("https://push.example.com/send/shared-phone")
    sign_in @alice
    with_push_keys { post push_subscription_path, params: { subscription: shared_phone }, as: :json }
    assert_equal @alice, PushSubscription.find_by!(endpoint: shared_phone[:endpoint]).profile

    cookies.delete("_household_session") # Alice's session ended without her signing out
    sign_in @bob
    with_push_keys do
      assert_no_difference -> { PushSubscription.count } do
        post push_subscription_path, params: { subscription: shared_phone }, as: :json
      end
    end

    assert_response :created
    assert_equal @bob, PushSubscription.find_by!(endpoint: shared_phone[:endpoint]).profile
  end

  test "an endpoint learnt elsewhere moves nobody's subscription: only its own browser can" do
    alices = push_subscription_for(@alice, endpoint: "https://push.example.com/send/alice")

    with_push_keys do
      post push_subscription_path, params: { subscription: browser_subscription(alices.endpoint) }, as: :json
    end

    assert_response :conflict
    alices.reload
    assert_equal [ @alice, "auth" ], [ alices.profile, alices.auth_key ], "still hers, with her browser's keys"
  end

  test "without VAPID keys on the server, nobody can subscribe" do
    post push_subscription_path, params: { subscription: browser_subscription }, as: :json

    assert_response :forbidden
    assert_equal 0, PushSubscription.count
  end

  test "an endpoint that isn't a push service's is refused" do
    with_push_keys do
      assert_no_difference -> { PushSubscription.count } do
        post push_subscription_path, params: { subscription: browser_subscription("http://attacker.example/") }, as: :json
      end
    end

    assert_response :unprocessable_content
  end

  test "turning them off removes this device, and only one's own" do
    mine = push_subscription_for(@bob)
    theirs = push_subscription_for(@alice)

    delete push_subscription_path, params: { endpoint: theirs.endpoint }, as: :json
    delete push_subscription_path, params: { endpoint: mine.endpoint }, as: :json

    assert_response :no_content
    assert_equal [ theirs ], PushSubscription.all.to_a
  end

  test "the service worker swaps a rotated subscription for the one it replaces" do
    old = push_subscription_for(@bob, endpoint: "https://push.example.com/send/old")

    with_push_keys do
      patch push_subscription_path, params: { old_endpoint: old.endpoint, subscription: browser_subscription("https://push.example.com/send/new") }, as: :json
    end

    assert_response :no_content
    assert_equal "https://push.example.com/send/new", old.reload.endpoint
  end

  test "a rotation can't take over someone else's device" do
    theirs = push_subscription_for(@alice, endpoint: "https://push.example.com/send/alice")

    with_push_keys do
      patch push_subscription_path, params: { old_endpoint: theirs.endpoint, subscription: browser_subscription("https://push.example.com/send/new") }, as: :json
    end

    assert_response :not_found
    assert_equal "https://push.example.com/send/alice", theirs.reload.endpoint
  end

  test "signing out stops this device's notifications" do
    with_push_keys do
      post push_subscription_path, params: { subscription: browser_subscription("https://push.example.com/send/bob") }, as: :json
    end
    other_device = push_subscription_for(@bob)

    delete destroy_profile_session_path

    assert_equal [ other_device ], @bob.push_subscriptions.reload.to_a
  end

  test "signing out after the browser was closed and reopened stops this device's notifications too" do
    sign_out :profile
    @bob.update!(password: "a-long-password")
    post profile_session_path, params: { profile: { login: @bob.username, password: "a-long-password", remember_me: "1" } }
    with_push_keys do
      post push_subscription_path, params: { subscription: browser_subscription("https://push.example.com/send/bob") }, as: :json
    end
    assert_response :created

    cookies.delete("_household_session") # the browser closed: "Remember me" signs Bob back in, in a new session
    get root_path
    assert_select "form[action=?]", destroy_profile_session_path
    delete destroy_profile_session_path

    assert_not PushSubscription.exists?(endpoint: "https://push.example.com/send/bob")
  end

  test "with push off, nobody subscribes a device, keys or not" do
    sign_in profiles(:alice)

    with_env("PUSH_NOTIFICATIONS" => "off") do
      with_push_keys do
        post push_subscription_path, params: { subscription: browser_subscription }, as: :json
        assert_equal 0, PushSubscription.count

        get root_path
        assert_match I18n.t("push.unavailable.not_configured"), response.body
        assert_select "[data-controller~=push]", 0
      end
    end
  end

  test "the navbar's switch knows this person's devices by digest, never by endpoint" do
    mine = push_subscription_for(@bob)

    with_push_keys { get root_path }

    assert_select "[data-controller~=push][data-push-digests-value*=?]", PushSubscription.digest(mine.endpoint)
    assert_not_includes response.body, mine.endpoint
  end
end
