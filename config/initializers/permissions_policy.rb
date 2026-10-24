# frozen_string_literal: true

# The Permissions-Policy on every response: the browser features this app
# uses are allowed to its own pages, and the others below are off, for the
# app and for anything it might ever embed.
#
# - camera, autoplay: the barcode scanner shows the camera's stream, muted.
# - screen-wake-lock: the upload modal keeps the screen on while files go up.
#
# Push notifications aren't a policy feature: the browser asks for them
# itself. Copying a link keeps the clipboard's default, this app's pages.
#
# Only names Chromium knows: it warns on every page about one it doesn't
# (ambient-light-sensor, web-share). A default header rather than
# config.permissions_policy: Rails' DSL still writes the Feature-Policy
# header that Permissions-Policy replaced.
Rails.application.configure do
  allowed = %w[autoplay camera screen-wake-lock]
  denied = %w[
    accelerometer display-capture encrypted-media fullscreen geolocation gyroscope hid idle-detection
    keyboard-map magnetometer microphone midi payment picture-in-picture serial sync-xhr usb
  ]

  config.action_dispatch.default_headers["Permissions-Policy"] =
    [ *allowed.map { "#{_1}=(self)" }, *denied.map { "#{_1}=()" } ].join(", ")
end
