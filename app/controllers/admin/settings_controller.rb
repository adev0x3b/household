# frozen_string_literal: true

# /admin/settings — what the admin sets for the whole installation, one card
# per section (Installation::*): what it allows, the bookshelf's sources, the
# GitHub token /admin/deployment's buttons use, the demo household's
# password. Admins only. A secret never comes back to the page; a blank
# field keeps the saved value. A save waits for the admin's password
# (Admin::Sudo): a stolen session could otherwise point the deploy buttons
# at a token of its own. Forgetting a value doesn't, since the
# environment's value or nothing takes its place. The assistant's own
# settings are /assistant/settings.
#   show / update   the page and its form
#   clear           forgets one saved secret (the environment's, if any, takes over)
class Admin::SettingsController < Admin::BaseController
  SECTIONS = [ Installation::Allowances, Installation::Books, Installation::DeployToken, Installation::DemoPassword ].freeze

  def show
    render_page settings_page(SECTIONS.to_h { |section| [ section.param_key, section.current ] })
  end

  def update
    sections = SECTIONS.to_h { |section| [ section.param_key, section.current.assign(section_params(section)) ] }
    if !sudo.passed?(params.dig(:settings, :password))
      render_page settings_page(sections, wrong_password: true), status: :unprocessable_content
    elsif Installation::Save.call(sections.values, by: current_profile).success?
      toast_flash(:success, t("admin.settings.notices.saved"))
      check_deploy_token if sections.fetch(:deploy_token).deploy_dispatch_token.present?
      redirect_to admin_settings_path, status: :see_other
    else
      render_page settings_page(sections), status: :unprocessable_content
    end
  end

  # The key is one of Platform::KEYS: the route says so.
  def clear
    key = params[:key]
    Platform::Setting.first&.update!(key => nil, updated_by: current_profile)
    toast_flash(:success, t("admin.settings.notices.cleared", name: t("installation.secret.names.#{key}")))
    redirect_to admin_settings_path, status: :see_other
  end

  private

  def section_params(section) = params.fetch(:settings, {}).fetch(section.param_key, {}).permit(*section.attribute_names)

  def settings_page(sections, wrong_password: false)
    Views::Admin::Settings::Show.new(sections: sections, token_expiry: Delivery::TokenExpiry.current,
                                     ask_password: sudo.required?, wrong_password: wrong_password)
  end

  # A token just saved is tried at once on what the Deployment page reads
  # (its writes would start something): what it can't read is named, with
  # the permission it lacks. Its expiry, if GitHub says, is kept for the page.
  def check_deploy_token
    failed = Delivery::Github.check.reject { |_read, ok| ok == true }
    return if failed.empty?

    toast_flash(:alert, t("admin.settings.token.partial", list: failed.map { |read, error| "#{t("admin.settings.token.reads.#{read}")} (#{error})" }.to_sentence,
                                                          repository: Deployment.repositories.to_sentence))
  end
end
