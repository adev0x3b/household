# frozen_string_literal: true

source "https://rubygems.org"

# How versions are held: a gem the app's own code or configuration is written
# against keeps to its major release, from the minor the code needs ("~> 2.4"),
# or to its minor while it is still on 0.x ("~> 0.17.0"). Rails keeps to its
# minor, since each one brings new defaults. The gems Rails' generator adds,
# used as generated, are left free: Rails keeps them working together, and
# Gemfile.lock holds every exact version.

# The framework, and what Rails' generator adds around it.
gem "rails", "~> 8.1.0"
gem "pg"
gem "puma"
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
# Compresses and caches the assets in front of Puma, in the image's command (Dockerfile).
gem "thruster", require: false
# Required in config/boot.rb.
gem "bootsnap", require: false
# Windows has no zoneinfo files of its own.
gem "tzinfo-data", platforms: %i[ windows jruby ]

# The cache, the jobs and Action Cable, each in a database of its own (config/database.yml).
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
# The jobs, failed ones retried or discarded, on /admin/jobs.
gem "mission_control-jobs", "~> 1.3"
# Errors reported through Rails.error, kept in a database of their own and read
# on /admin/errors. 0.9.1 or later: 0.9.0 recorded every request's params and
# every job's arguments with each error, and the app's logs hold ids only.
gem "solid_errors", "~> 0.9.1"
# Refuses a migration the version still serving can't survive. In every group,
# since production runs the migrations, and their safety_assured blocks, when it boots.
gem "strong_migrations", "~> 2.8"

# Signing in (Profile, by username or email) and invitations, the only way in.
gem "devise", "~> 5.0"
gem "devise_invitable", "~> 2.0"
# Passwords, for Devise and for a file link that has one (UploadLink).
gem "bcrypt", "~> 3.1"
# Who may do what (app/policies).
gem "pundit", "~> 2.5"

# Views and components as Ruby classes (app/views, app/components).
gem "phlex-rails", "~> 2.4"
# The stylesheets: Dart Sass, and the Bulma framework they build on.
gem "dartsass-rails", "~> 0.5.1"
gem "bulma-rails", "~> 1.0"
# Paged lists.
gem "will_paginate", "~> 4.0"

# Repeating series, from their RFC 5545 rule (Events::RecurrenceRule, Events::Schedule).
gem "ice_cube", "~> 0.17.0"

# A file's content type from its bytes, never from its name (Uploads::Storage,
# Messages::CleanPicture).
gem "marcel", "~> 1.2"
# A message's pictures, shrunk for the page (Message's :shown variant) and saved
# again without their metadata (Messages::CleanPicture).
gem "image_processing", "~> 2.2"
# libvips, the one image library: image_processing's backend, and what prepares a
# photo of a lab report for Tesseract (LabReports::Ocr). Active Storage and the OCR
# load it themselves, so a machine without libvips still boots.
gem "ruby-vips", "~> 2.3", require: false

# The assistant's model providers: Ollama, Anthropic, OpenAI.
gem "ruby_llm", "~> 2.1"
# Notifications pushed to devices (VAPID, aes128gcm).
gem "web-push", "~> 3.1"
# .env in development, and in production the secrets each server makes on its
# first boot (config/application.rb).
gem "dotenv", "~> 3.2"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  # Security checks CI runs: known advisories for the locked gems
  # (config/bundler-audit.yml), and the app's own code.
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  # Rails' style, then slow idioms and Minitest's assertions on top (.rubocop.yml).
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-performance", "~> 1.27", require: false
  gem "rubocop-minitest", "~> 0.41.0", require: false
  # Missing, unused and untranslated keys in config/locales (test/i18n_test.rb).
  gem "i18n-tasks", "~> 1.1", require: false
end

group :development do
  gem "web-console"
  # Deploys the images CI builds (config/deploy.yml and a file per destination).
  gem "kamal", "~> 2.12", require: false
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  # Line and branch coverage of every run, with a floor CI enforces (.simplecov).
  gem "simplecov", "~> 1.3", require: false
  # Fails a test that runs N+1 queries (test/test_helper.rb); pg_query
  # fingerprints Postgres' SQL for it.
  gem "prosopite", "~> 2.2", require: false
  gem "pg_query", "~> 6.2", require: false
end
