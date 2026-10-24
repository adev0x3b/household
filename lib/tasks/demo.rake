# frozen_string_literal: true

namespace :demo do
  desc "Rebuild the demo household from scratch: three people, six months of activity ending today (the password saved on /admin/settings, else DEMO_PASSWORD)"
  task seed: :environment do
    Demo::Seeder.call
  end

  desc "Delete the demo household and everything in it"
  task remove: :environment do
    household = Demo::Seeder.household or abort "There is no demo household."
    Households::Destroy.call(household)
    puts "Removed #{household.name}."
  end
end

namespace :demo do
  desc "An admin for a private copy with the demo's data (dev, bin/preview-dev --fresh, or a development machine): `admin`, with the demo's password, in a household of their own. Refused anywhere else, since that password is public (admin:create there)"
  task admin: :environment do
    unless Rails.env.development? || Deployment.destination == "dev"
      abort "Only on dev or a development machine: the demo's password is public. Use admin:create with a strong one."
    end
    abort "There is an admin already: #{Profile.admin.first.username}." if Profile.admin.exists?

    result = Admins::Create.call(household_name: "Admin", username: "admin", email: "admin@#{ENV.fetch("APP_HOST", "example.com")}",
                                 password: Platform.demo_password)
    profile = result.profile
    abort "Nothing was created: #{profile.errors.full_messages.join(", ")}" if result.failure?

    puts "Created #{profile.username} <#{profile.email}>, an admin, with the demo's password."
  end
end
