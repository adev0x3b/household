# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Toastable
  include Modals
  include RedirectsAfterWrites
  include NavbarPageControls

  # The page that refuses an old browser is in the reader's language, so the
  # language is known first.
  before_action :set_locale
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern, block: :refuse_browser
  around_action :in_viewer_zone
  before_action :redirect_to_setup, unless: :profile_signed_in?
  before_action :authenticate_profile!
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Pundit: Use Profile instead of User
  def pundit_user
    current_profile
  end

  # What the layout's bar shows about the person signed in (Navbar::Facts).
  helper_method :navbar_facts
  def navbar_facts = @navbar_facts ||= Navbar::Facts.for(current_profile)

  # Who the demo's banner offers to look at the household as (Platform.open_profiles).
  helper_method :open_profiles
  def open_profiles = @open_profiles ||= Platform.open_profiles

  # Every action asks Pundit — authorize a record or a question, or
  # policy_scope for a list of records — or says why it doesn't
  # (without_authorization): a new action without a check fails its first
  # request. Devise's own pages are Devise's (sign-in, password, invitation tokens).
  after_action :verify_pundit_consulted, unless: :devise_controller?

  # What each controller exempts from the checks and why, for review
  # (test/integration/authorization_test.rb lists them all).
  class_attribute :authorization_exemptions, instance_writer: false, default: {}

  # Actions that read nothing of anyone else's — a public page, the
  # person's own settings, a page built only from what they may read —
  # skip Pundit's checks, saying why.
  def self.without_authorization(reason, only:)
    actions = Array(only).map(&:to_s)
    skip_after_action :verify_pundit_consulted, only: actions
    self.authorization_exemptions = authorization_exemptions.merge(actions.index_with { reason })
  end

  # A limit on what one person does, from wherever they do it: a household
  # shares one address behind its router. Over it, the answer is
  # #rate_limited's unless the controller words its own.
  def self.rate_limit_per_person(to:, within:, with: -> { rate_limited }, **options)
    rate_limit(to: to, within: within, by: -> { current_profile.id }, with: with, **options)
  end

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::InvalidAuthenticityToken, with: :page_out_of_date
  rescue_from ActiveRecord::StaleObjectError, with: :changed_meanwhile

  protected

  # A fresh database has nobody to sign in: the setup page makes the first
  # account (SetupController), and every visitor goes there until then.
  def redirect_to_setup
    redirect_to setup_path if Profile.none?
  end

  # Every request reckons on its viewer's clock: their "today",
  # their times, wherever the server runs; before sign-in, the app's
  # (config.time_zone).
  def in_viewer_zone(&) = Time.use_zone(current_profile&.zone || Time.zone, &)

  def set_locale
    browser = AcceptLanguage.new(request.headers["Accept-Language"]).locale
    I18n.locale = current_profile&.locale.presence || browser || I18n.default_locale
    remember_locale if profile_signed_in?
  end

  # An error page is served without the app, so it can't ask who the person
  # is: the session tells it the language they were reading (ErrorPages).
  # A stranger's language is only their browser's, which the page reads
  # itself.
  def remember_locale
    session[ErrorPages::SESSION_KEY] = I18n.locale.to_s
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit :sign_in, keys: [ :login, :password ]
    devise_parameter_sanitizer.permit :accept_invitation, keys: [ :username, :first_name, :last_name ]
  end

  private

  def refuse_browser
    page = Rails.public_path.join(Views::PublicPages::Error.file(:not_acceptable, I18n.locale))
    render file: page, layout: false, status: :not_acceptable
  end

  def verify_pundit_consulted
    return if pundit_policy_authorized? || pundit_policy_scoped?

    raise Pundit::AuthorizationNotPerformedError, self.class
  end

  # Over a rate limit (`rate_limit …, with: -> { rate_limited }`, the
  # default of rate_limit_per_person): a Turbo
  # Stream request gets a toast and 429 where it stands, JSON a 429 with the
  # reason, a page the alert back where it was — or at `to` — by 303.
  def rate_limited(to: nil)
    message = t("rate_limit.exceeded")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: toast(:alert, message), status: :too_many_requests }
      format.json { render json: { error: message }, status: :too_many_requests }
      format.any do
        toast_flash(:alert, message)
        to ? redirect_to(to, status: :see_other) : redirect_back(fallback_location: root_path, status: :see_other)
      end
    end
  end

  # Refused for a reason the person can act on (the ingredient is still in a
  # recipe, the ISBN can't be read): the reason as a toast and a 422 where
  # they stand, so nothing on the page is lost; a page goes back with it, by
  # 303. A success, by contrast, is a visit (RedirectsAfterWrites).
  def refuse(reason)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: toast(:alert, reason), status: :unprocessable_content }
      format.json { render json: { error: reason }, status: :unprocessable_content }
      format.any do
        toast_flash(:alert, reason)
        redirect_back(fallback_location: root_path, status: :see_other)
      end
    end
  end

  # Not allowed: a Turbo Stream request gets a toast and 403 where it stands; a
  # page goes back, by 303 — a 302 would replay a PATCH or DELETE (fetch
  # keeps the method) at the previous page's address.
  def user_not_authorized
    respond_to do |format|
      format.turbo_stream { render turbo_stream: toast(:alert, t("pundit.not_authorized")), status: :forbidden }
      format.json { head :forbidden }
      format.any do
        toast_flash(:alert, t("pundit.not_authorized"))
        redirect_back(fallback_location: root_path, status: :see_other)
      end
    end
  end

  # Gone before the press reached it, as when a housemate deleted it a moment
  # ago, or never theirs to see, which reads the same (tenancy): the person
  # is told where they stand.
  def record_not_found(error)
    answer_in_place(t("failures.gone"), status: :not_found, or_raise: error)
  end

  # The form's token no longer matches the session, as after signing out and
  # in again in another tab: nothing was done, and the page needs reloading.
  def page_out_of_date(error)
    answer_in_place(t("failures.page_out_of_date"), status: :unprocessable_content, or_raise: error)
  end

  # Someone saved the thing after this copy of it was read. A form that
  # edits it says so on the form and keeps what was typed (EditedTogether);
  # anything else is refused here and its page brought up to date.
  def changed_meanwhile(error)
    answer_in_place(t("failures.changed_meanwhile"), status: :conflict, or_raise: error)
  end

  # A failure the person can only be told about: a toast with the status
  # for a Turbo Stream request, and the page brought up to date, since what
  # it shows (the thing that is gone, the form's token) is what failed. The
  # reason alone for JSON. A page Turbo asked for goes back to the one it
  # came from, with the toast, unless that is the page that failed, which
  # nobody can stay on. A page opened directly has no page to stay on, and
  # gets Rails' public page for the status.
  def answer_in_place(message, status:, or_raise:)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: [ toast(:alert, message), page_refresh ], status: status }
      format.json { render json: { error: message }, status: status }
      format.any do
        raise or_raise unless turbo_request?

        toast_flash(:alert, message)
        redirect_to page_before_this, status: :see_other
      end
    end
  end

  # Turbo leaves out a refresh named after a request of its own page, as an
  # echo of that page's own change; this one is meant for it.
  def page_refresh = turbo_stream.refresh(request_id: nil)

  # Turbo names every request it sends (turbo-rails reads the same header to
  # tell its refreshes apart); the browser's own navigation names none.
  def turbo_request? = request.headers["X-Turbo-Request-Id"].present?

  def page_before_this
    back = url_from(request.referer)
    back && URI(back).path != request.path ? back : root_path
  end
end
