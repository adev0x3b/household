# frozen_string_literal: true

# A page whose address carries a token, as a link mailed to someone does:
# the browser never tells another site the address it came from. The app
# itself still hears it, since it holds the token already: with no
# referrer at all, a form's press says its origin is "null", which Rails
# refuses as forgery, and a refusal can't go back to the page.
module TokenInAddress
  extend ActiveSupport::Concern

  included do
    before_action { response.set_header("Referrer-Policy", "same-origin") }
  end
end
