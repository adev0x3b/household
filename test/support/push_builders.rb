# frozen_string_literal: true

module PushBuilders
  VAPID = WebPush.generate_key

  # Push turned on (VAPID keys in the environment) for the block.
  def with_push_keys(&)
    with_env("VAPID_PUBLIC_KEY" => VAPID.public_key, "VAPID_PRIVATE_KEY" => VAPID.private_key, &)
  end

  def push_subscription_for(profile, endpoint: "https://push.example.com/send/#{SecureRandom.hex(8)}", origin: "https://household.example")
    profile.push_subscriptions.create!(endpoint: endpoint, p256dh_key: "p256dh", auth_key: "auth", origin: origin)
  end

  # What a browser's PushSubscription.toJSON() sends.
  def browser_subscription(endpoint = "https://push.example.com/send/#{SecureRandom.hex(8)}")
    { endpoint: endpoint, keys: { p256dh: "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM", auth: "tBHItJI5svbpez7KI4CCXg" } }
  end
end
