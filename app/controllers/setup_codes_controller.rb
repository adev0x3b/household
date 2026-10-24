# frozen_string_literal: true

# /setup/code: the one-time code the setup page asks for first, so whoever
# finds a fresh copy's address before its owner can't make the first
# account. The right code opens the setup for this browser's session, and
# keeps working until the first account exists, so a closed tab can come
# back. A wrong one is refused with the same words every time, under the
# setup page's rate limit.
class SetupCodesController < ApplicationController
  # The digest of the code this session gave. A new code (SetupCodes::Renew)
  # has another digest, so it shuts out whoever gave the old one.
  SESSION_KEY = :setup_code_digest

  include FirstSetupPages

  without_authorization "the setup page's code, on a database with no profile yet", only: :create

  rate_limit to: 5, within: 1.minute, only: :create, with: -> { rate_limited(to: setup_path) }

  def create
    digest = Platform.setup_code_digest
    if SetupCode.accepts?(params.dig(:setup_code, :code), digest)
      session[SESSION_KEY] = digest
      redirect_to setup_path, status: :see_other
    else
      render_page Views::Setup::Code.new(available: digest.present?, wrong: true), status: :unprocessable_content
    end
  end
end
