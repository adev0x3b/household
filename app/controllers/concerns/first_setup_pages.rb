# frozen_string_literal: true

# What every page of a fresh copy's first setup shares: it is open to
# visitors who aren't signed in, and only while the database holds nobody,
# since there is no sign-up once anyone exists.
module FirstSetupPages
  extend ActiveSupport::Concern

  included do
    skip_before_action :redirect_to_setup
    skip_before_action :authenticate_profile!
    before_action :only_on_an_empty_database
  end

  private

  def only_on_an_empty_database
    redirect_to new_profile_session_path unless Profile.none?
  end

  # Whether this browser gave the copy's current setup code
  # (SetupCodesController). A new code shuts out whoever gave the old one.
  def setup_code_given?
    digest = Platform.setup_code_digest
    digest.present? && ActiveSupport::SecurityUtils.secure_compare(session[SetupCodesController::SESSION_KEY].to_s, digest)
  end

  # For what the setup page asks while it is open; the page itself asks for
  # the code instead.
  def refuse_without_the_setup_code
    head :forbidden unless setup_code_given?
  end
end
