# frozen_string_literal: true

namespace :admin do
  desc "The first sign-in on a fresh database: a household and its admin (USERNAME, EMAIL, PASSWORD, HOUSEHOLD=its name); the setup page does the same in the browser"
  task create: :environment do
    username, email, password = ENV.values_at("USERNAME", "EMAIL", "PASSWORD")
    abort "USERNAME, EMAIL and PASSWORD are needed, e.g. USERNAME=alex EMAIL=alex@example.com PASSWORD=… bin/rails admin:create" if [ username, email, password ].any?(&:blank?)

    result = Admins::Create.call(household_name: ENV.fetch("HOUSEHOLD", "Household"), username: username, email: email, password: password)
    profile = result.profile
    abort "Nothing was created: #{profile.errors.full_messages.join(", ")}" if result.failure?

    puts "Created #{profile.household.name}: #{profile.username} <#{profile.email}> can sign in and manage households on /admin/households."
  end
end
