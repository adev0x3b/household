# frozen_string_literal: true

# /demo — the demo's front door. The demo is an installation of its own
# (config/deploy.demo.yml) whose accounts are open: anyone enters as one of
# them, with no password (Platform.open_accounts). There, the sign-in page
# offers them as buttons, and entering is a POST here (create), like the
# banner's switch (Views::Layouts::DemoBanner): a GET signs nobody in, so
# neither a hovered link (Turbo prefetches it) nor another site can. Only ever
# an open account, by its username.
#
# On any other copy, /demo sends the visitor to the demo installation
# (DEMO_HOST, Deployment.url) — the link handed out keeps working — or is
# nothing where there is none.
class DemosController < ApplicationController
  without_authorization "public: the way into the demo's open accounts, and nobody else's", only: %i[show create]

  skip_before_action :authenticate_profile!
  rate_limit to: 20, within: 1.minute, with: -> { rate_limited(to: new_profile_session_path) }

  def show
    if Platform.open_accounts.any? then redirect_to new_profile_session_path
    elsif (demo = Deployment.url(:demo)) then redirect_to "#{demo}/demo", allow_other_host: true
    else raise ActionController::RoutingError, "No demo here"
    end
  end

  # Coming from outside, a word about what this is; switching accounts from
  # the banner, none.
  def create
    profile = Platform.open_profile(params[:as]) or raise ActionController::RoutingError, "Not an open account"
    welcome = !Platform.open_account?(current_profile)

    # Everyone's account: a stranger's wrong passwords never keep the next visitor out.
    profile.unlock_access! if profile.access_locked?
    sign_in(:profile, profile)
    toast_flash(:notice, t("demo.welcome")) if welcome
    redirect_to root_path, status: :see_other
  end
end
