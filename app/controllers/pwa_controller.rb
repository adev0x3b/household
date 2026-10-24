# frozen_string_literal: true

# What makes Household an installable app (a PWA): its manifest, its service
# worker, and the page the service worker shows when there's no network.
# Public, like Rails::PwaController: the browser fetches them without a
# session. Never cached on the way (the app is served through a CDN tunnel,
# and a stale service worker would keep old code running on every device).
class PwaController < ApplicationController
  without_authorization "public: the installed app's own files", only: %i[manifest service_worker offline]

  skip_before_action :authenticate_profile!
  skip_before_action :redirect_to_setup
  # A service worker is JavaScript fetched by the browser itself, not by one
  # of our pages: Rails would otherwise refuse it as a cross-origin script.
  skip_forgery_protection

  before_action { response.headers["Cache-Control"] = "no-cache" }

  def manifest
    render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json", layout: false
  end

  def service_worker
    response.headers["Service-Worker-Allowed"] = helpers.pwa_scope
    render template: "pwa/service-worker", formats: :js, content_type: "text/javascript", layout: false
  end

  # Precached by the service worker in every language: it shows the one the
  # browser asks for, since a shared tablet's people may each read another.
  def offline
    I18n.with_locale(params[:locale]) { render template: "pwa/offline", formats: :html, layout: false }
  end
end
