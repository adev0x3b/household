# frozen_string_literal: true

# A forgotten password: asking for a link by mail, where the installation
# mails, and setting a new password from a link, mailed or made on the
# household page (Profiles::PasswordLink).
class Profiles::PasswordsController < Devise::PasswordsController
  include MailEnabled
  include TokenInAddress

  before_action :mail_enabled!, only: %i[new create]

  # A link's token can't be guessed; trying anyway is slowed like signing in.
  rate_limit to: 10, within: 3.minutes, only: :update, name: "link", with: -> { rate_limited }
  # Each request may mail someone: few from one address.
  rate_limit to: 5, within: 1.hour, only: :create, name: "forgot", with: -> { rate_limited(to: new_profile_password_path) }

  # GET /profiles/password/new
  def new
    render_page Views::Devise::Passwords::New.new
  end

  # POST /profiles/password
  # The same answer whoever was asked for, after the same work: one lookup,
  # and a job that decides (Profiles::PasswordLinkRequestJob), so neither the
  # page nor its time says whether the account exists.
  def create
    profile = Profile.find_for_database_authentication(login: params.expect(profile: [ :login ])[:login].to_s)
    Profiles::PasswordLinkRequestJob.perform_later(profile&.id)
    toast_flash(:notice, t("passwords.notices.asked", minutes: Profile::SHORT_PASSWORD_LINK_FOR.in_minutes.to_i))
    redirect_to new_profile_session_path, status: :see_other
  end

  # GET /profiles/password/edit?reset_password_token=...
  def edit
    super
    render form
  end

  # PUT /profiles/password
  def update
    super do |profile|
      return render form, status: :unprocessable_content if profile.errors.any?

      Profiles::AfterPasswordChange.call(profile, device: cookies.signed[PushSubscriptionsController::DEVICE_COOKIE])
    end
  end

  protected

  # The link's form as Devise reads it: a body that isn't that form is a
  # bad request, as anywhere else, rather than an error in Devise's lookup.
  def resource_params = params.expect(profile: %i[reset_password_token password password_confirmation])

  # A password set from a link opens an account locked by wrong passwords:
  # the link came from whoever runs the household, or to the person's
  # confirmed address (Devise only does this when unlocking goes by email,
  # which it doesn't here).
  def unlockable?(resource) = resource.respond_to?(:unlock_access!)

  private

  def form = Views::Devise::Passwords::Edit.new(resource: resource, resource_name: resource_name)
end
