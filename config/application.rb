# frozen_string_literal: true

require_relative "boot"

# The frameworks the app uses: not Action Mailbox (it would draw the
# inbound-email routes of five providers) or Action Text.
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

# In Docker, what bin/docker-secrets made on the container's first boot
# (bin/docker-secrets says what each is): the secret key base, the Active Record encryption
# keys, the Web Push pair. Read here so every process of the container gets
# them — the web server, the jobs, a console. The environment wins (Dotenv
# never overwrites), and there is no such file outside Docker.
Dotenv.load(ENV.fetch("SECRETS_FILE", "/rails/secrets/env"))

# Not `Household`: that name is the model's (app/models/household.rb).
module HouseholdApp
  class Application < Rails::Application
    config.load_defaults 8.1

    # No file by Active Storage's own routes: their signed URLs never expire
    # and need no sign-in. A message's pictures and the assistant's photos
    # go through controllers that authorize them (ServesAttachments).
    config.active_storage.draw_routes = false

    # Nor Turbo Native's: an installed app here is a PWA, not a native shell.
    config.turbo.draw_routes = false

    # lib holds code the app loads like its own, except the rake tasks, which
    # Rake loads, and the custom cops, which RuboCop alone loads (.rubocop.yml).
    config.autoload_lib(ignore: %w[tasks rubocop])

    # Only the languages the app is translated into; gems ship many more.
    config.i18n.available_locales = %i[en it]

    # A failed request's page from public/, in its reader's language. Found
    # when a request fails rather than now, since lib loads after this file.
    config.exceptions_app = ->(env) { ErrorPages.new(Rails.public_path).call(env) }

    # The path the app is served under on its domain: the root, unless
    # MOUNT_PATH names one ("/love": it then shares the domain). The routes,
    # the health check, the installed app's scope and kamal-proxy's health
    # check derive from it; empty when the app is at the root.
    config.x.mount_path = ENV["MOUNT_PATH"].to_s.gsub(%r{\A/+|/+\z}, "").then { _1.empty? ? "" : "/#{_1}" }

    # Every cookie the app sets is sent back to its own path only: under a
    # mount path the domain's other apps would otherwise receive the session.
    config.x.cookie_path = config.x.mount_path.presence || "/"

    # The cookie's name came from the application's module name; kept as it
    # was, so renaming the module signs nobody out.
    config.session_store :cookie_store, key: "_household_session", path: config.x.cookie_path

    # Who the app's mail would come from (Devise's sender): MAIL_FROM, else
    # the address at the app's own host. No mail is sent today: links are
    # shown once instead.
    config.x.mail_from = ENV.fetch("MAIL_FROM") { "noreply@#{ENV.fetch("APP_HOST", "localhost")}" }

    # Whether the setup page may make its own one-time code and print it where
    # the server runs. A copy that is installed gets its code from the machine
    # (bin/rails setup:code), and never writes one to a log it keeps.
    config.x.makes_its_own_setup_code = false

    # Errors reported through Rails.error are kept by Solid Errors
    # and read on /admin/errors; Solid Queue's jobs on /admin/jobs (Mission
    # Control). Both are the admin's, behind their sign-in (config/routes.rb,
    # Admin::EnginesController) rather than HTTP basic auth; no email.
    config.solid_errors.base_controller_class = "Admin::EnginesController"
    config.solid_errors.destroy_after = 30.days
    config.mission_control.jobs.base_controller_class = "Admin::EnginesController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    # The clock before anyone signs in, and for work done for no one in
    # particular: TIME_ZONE, an IANA name, else UTC. A signed-in
    # request runs on its viewer's (ApplicationController#in_viewer_zone).
    config.time_zone = ENV["TIME_ZONE"].presence || "UTC"
  end
end
