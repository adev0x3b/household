# frozen_string_literal: true

module ApplicationHelper
  # The installed app's scope: the manifest's start and scope, and where the
  # service worker acts. The app's root as its pages link it (the mount
  # path, empty at the root, no trailing slash), so the home page itself is in it; the worker is served from
  # inside it, so PwaController allows it that much (Service-Worker-Allowed).
  def pwa_scope = root_path
end
