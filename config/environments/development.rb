# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Jobs that opt out of the web server (ApplicationJob.runs_outside_web_server) go to
  # Solid Queue, worked by bin/jobs; the rest stay in-process (async), so the
  # assistant's streamed replies keep reaching the browser over the async cable.
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Reported errors in their own database, as in production (/admin/errors).
  config.solid_errors.connects_to = { database: { writing: :errors } }

  # Use solid_cache_store for parity with production (cross-process subscription tracking).
  config.cache_store = :solid_cache_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false

  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # A tunnel's hostname pointing at this server (DEV_TUNNEL_HOST), so a phone
  # reaches it over HTTPS: a secure context, which the camera and push need.
  if (tunnel = ENV["DEV_TUNNEL_HOST"].presence)
    config.hosts << tunnel
    config.action_cable.allowed_request_origins = [ "http://localhost:3000", "https://#{tunnel}" ]
  end

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # A development server is reachable on the network (Procfile.dev binds every
  # address) and can be put on a public tunnel, so its setup page asks for a
  # code too. Nothing installs it, so it makes the code itself and prints it
  # in bin/dev's output.
  config.x.makes_its_own_setup_code = true
end
