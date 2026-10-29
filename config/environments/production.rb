# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Downloads of the Files section (UploadsController#file) are handed
  # to Thruster with this header: it streams the file itself, ranges
  # included, and Puma is free for the next request.
  config.action_dispatch.x_sendfile_header = "X-Sendfile"

  # Behind something that terminates HTTPS — the Cloudflare Tunnel, a reverse
  # proxy — which is the norm: every request is assumed secure, and forced so
  # (Strict-Transport-Security, secure cookies). FORCE_SSL=off for a copy
  # reached over plain HTTP (compose.yml on a home network, docs/self-hosting.md):
  # the browser works; installing as an app and push need HTTPS.
  ssl = !%w[off false no 0].include?(ENV["FORCE_SSL"].to_s.strip.downcase)
  config.assume_ssl = ssl
  config.force_ssl = ssl

  # The health check, under the app's mount path (config/application.rb):
  # kamal-proxy's, and the deploy's smoke test, asked over plain http.
  health_check = "#{config.x.mount_path}/up"

  # Skip http-to-https redirect for the health check.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == health_check } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = health_check

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # The public name — the Cloudflare Tunnel's hostname — from the Kamal
  # destination's APP_HOST (config/deploy.*.yml); localhost only while the
  # image is built (assets precompile in production mode, with no destination).
  host = ENV.fetch("APP_HOST", "localhost")

  # Links made outside a request, a mail's, go where people open the app:
  # https://host, or over plain HTTP the port the copy is published on
  # (APP_PORT, from compose.yml).
  config.action_mailer.default_url_options = { host: host, protocol: ssl ? "https" : "http", port: (ENV["APP_PORT"].presence unless ssl) }.compact

  # The browser talks to /cable from the public origin only: https://host, or
  # over plain HTTP from whichever port the copy is published on.
  config.action_cable.allowed_request_origins = ssl ? [ "https://#{host}" ] : [ %r{\Ahttp://#{Regexp.escape(host)}(:\d+)?\z} ]

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks: the public
  # name (the Cloudflare Tunnel, through kamal-proxy) and localhost (curl inside the container).
  config.hosts = [ host, "localhost" ]

  # Skip DNS rebinding protection for the health check.
  config.host_authorization = { exclude: ->(request) { request.path == health_check } }

  # The Active Record encryption keys (Assistant::Setting's and Platform::Setting's
  # secrets): the ones bin/docker-secrets made on the first boot, kept in the
  # secrets volume. With RAILS_MASTER_KEY given instead, config/credentials.yml.enc's as usual.
  if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  end

  # Reported errors in their own database, like the queue, cache and cable.
  config.solid_errors.connects_to = { database: { writing: :errors } }
end
