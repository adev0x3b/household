# frozen_string_literal: true

class Profiles::SessionsController < Devise::SessionsController
  # Guessing passwords gets slow fast.
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { rate_limited(to: new_profile_session_path) }

  # Signing out also empties the browser's cache of this site: the pages and
  # pictures it kept, and its back/forward cache, so Back on a shared device
  # can't bring up the last person's pages (Clear-Site-Data).
  def destroy
    response.set_header("Clear-Site-Data", '"cache"')
    super
  end

  # GET /resource/sign_in
  def new
    self.resource = resource_class.new(sign_in_params)
    clean_up_passwords(resource)
    yield resource if block_given?
    render Views::Devise::Sessions::New.new(
      resource: resource,
      resource_name: resource_name,
      devise_mapping: devise_mapping,
      open_profiles: Platform.open_profiles,
      demo_url: (Deployment.url(:demo) if Platform.open_accounts.empty?)
    )
  end
end
