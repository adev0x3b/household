# frozen_string_literal: true

# The sample data is the demo household (Demo::Seeder, lib/demo): three
# people and six months of made-up activity ending today, lived through the
# app's own code. `bin/rails db:seed` — and db:prepare on a new database —
# builds it when there is none; SEED=demo (or `bin/rails demo:seed`)
# rebuilds it from scratch. Its members sign in as alex.demo, sam.demo or
# robin.demo with Platform.demo_password; on the demo installation their
# accounts are open (Platform.open_accounts, /demo). The setup page on
# an empty database, or `bin/rails admin:create`, makes an admin.
#
# The lexicon's starting languages, on every database, production included:
# the assistant matches supply names with them, and nothing else saves them.
LexiconLanguage.ensure_defaults!

# Never on a production database by itself: there the first account comes
# from the setup page, and the demo is a decision (SEED=demo).
if Rails.env.production? && ENV["SEED"].blank?
  puts "No demo household in production: the setup page makes the first account; SEED=demo adds the demo household."
  return
end

if ENV["SEED"] == "demo" || Demo::Seeder.household.nil?
  Demo::Seeder.call
else
  puts "The demo household is already there: SEED=demo (or bin/rails demo:seed) rebuilds it."
end
