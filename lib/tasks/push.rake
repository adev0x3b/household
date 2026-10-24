# frozen_string_literal: true

namespace :push do
  desc "Print a new VAPID key pair for Web Push, to put in .env"
  task :vapid_keys do
    require "web-push"
    key = WebPush.generate_key
    puts "VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{key.private_key}"
    puts "VAPID_SUBJECT=mailto:you@example.com"
    puts
    puts "Changing the pair later unsubscribes every device: they'll need to turn notifications on again."
  end
end
