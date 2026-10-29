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

  # The admin gets no link by mail when they forget their password, and
  # may be the only one who could make them one: whoever runs the machine can.
  desc "A link to set the password of USERNAME, printed here: it works once, for 30 minutes, and ends any link made before"
  task password_link: :environment do
    username = ENV["USERNAME"].to_s
    abort "USERNAME is needed, e.g. USERNAME=alex bin/rails admin:password_link" if username.blank?

    profile = Profile.joined.with_username(username).first
    abort "Nobody here goes by #{username}." if profile.nil?

    token = profile.short_password_link_token!
    url = Rails.application.routes.url_helpers.edit_profile_password_url(reset_password_token: token, **ActionMailer::Base.default_url_options)
    puts "Open this to set #{profile.username}'s password, within #{Profile::SHORT_PASSWORD_LINK_FOR.in_minutes.to_i} minutes:", url
  end
end
