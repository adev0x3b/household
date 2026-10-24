# frozen_string_literal: true

# /setup — the first setup of a fresh copy, in one form of short steps
# (Setup::Form): who sets it up, their household, what the installation
# allows, the assistant's model, the bookshelf's sources and who else lives
# there. Setup::Complete saves it all; the person is signed in as the admin
# and household owner. Every visitor lands here while the database has no
# profile at all (ApplicationController#redirect_to_setup); once anyone
# exists the page is gone, since there is no sign-up.
#
# The page asks for the copy's one-time setup code first (SetupCodesController),
# and shows nothing else to a browser that hasn't given it.
class SetupController < ApplicationController
  include FirstSetupPages

  without_authorization "the first account, on a database with no profile yet", only: %i[show create]

  before_action :ask_for_the_setup_code
  rate_limit to: 5, within: 1.minute, only: :create, with: -> { rate_limited(to: setup_path) }

  def show
    render_page Views::Setup::Show.new(form: Setup::Form.new)
  end

  def create
    form = Setup::Form.new(params.expect(setup: Setup::Form.fields))
    result = Setup::Complete.call(form)
    return render_page(Views::Setup::Show.new(form:), status: :unprocessable_content) if result.failure?

    session.delete(SetupCodesController::SESSION_KEY)
    sign_in(:profile, result.profile)
    # In the language the person just picked, which this request didn't know.
    result.profile.as_viewer { welcome(result) }
  end

  private

  def welcome(result)
    if result.invitations.any?
      # The links are readable only now, so they are shown in this answer
      # rather than after a redirect; the form is sent without Turbo.
      render_page Views::Setup::Done.new(household: result.profile.household, invitations: result.invitations)
    else
      toast_flash(:success, t("setup.notices.created", household: result.profile.household.name))
      redirect_to root_path, status: :see_other
    end
  end

  def ask_for_the_setup_code
    return if setup_code_given?

    if request.post?
      redirect_to setup_path, status: :see_other
    else
      digest = Platform.setup_code_digest
      digest ||= make_our_own_setup_code if Rails.configuration.x.makes_its_own_setup_code
      render_page Views::Setup::Code.new(available: digest.present?)
    end
  end

  # Printed, never logged: the code is for whoever runs the server, and is
  # worth nothing once the first account exists. Written to standard error
  # rather than through warn, which prints nothing while Ruby's warnings are
  # off (RUBYOPT=-W0, or a library silencing them for a moment).
  def make_our_own_setup_code
    code = SetupCodes::Renew.call.code
    $stderr.puts "\n  Household's setup code: #{code}\n  Open /setup and type it there. Lost it? bin/rails setup:code\n\n"
    Platform.setup_code_digest
  end
end
