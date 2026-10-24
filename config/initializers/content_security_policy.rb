# frozen_string_literal: true

# The Content-Security-Policy on every response: scripts, styles, fonts and
# connections come from this app alone, and nothing may frame it. What it
# lets in beyond 'self', and why:
#
# - script-src 'wasm-unsafe-eval': the barcode scanner compiles its
#   WebAssembly (zxing); no JavaScript eval.
# - img-src data: blob: — a picture's preview before it is sent (blob:),
#   images inlined in CSS (data:) — and the book covers' hosts: Open Library
#   (which hands them over to archive.org's servers) and Google Books.
# - media-src blob: — the camera's stream, while scanning a barcode.
# - style-src-attr 'unsafe-inline': style="…" attributes that carry a
#   computed value (a progress bar's width). <style> elements and
#   stylesheets still need 'self' or the nonce.
#
# The importmap's inline scripts and Turbo's progress bar carry the nonce
# (csp_meta_tag). A page Turbo brings in keeps the policy the document
# arrived with, so the nonce lasts as long as the session: made at random
# the first time a page asks (a first visit has no session id yet, the
# value Rails' template uses), kept when Devise renews the id at sign-in.
# Signing out or switching demo members loads a new document instead.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self
    policy.font_src :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.img_src :self, :data, :blob, "https://covers.openlibrary.org", "https://archive.org", "https://*.archive.org",
                   "https://books.google.com"
    policy.manifest_src :self
    policy.media_src :self, :blob
    policy.object_src :none
    policy.script_src :self, :wasm_unsafe_eval
    policy.style_src :self
    policy.style_src_attr :unsafe_inline
    policy.worker_src :self
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
