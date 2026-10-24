# frozen_string_literal: true

# The card at the foot of a settings page (the app's, the assistant's)
# that asks for the admin's password before a save. Not required in the
# browser: the assistant's Test button sends the same form, and saves nothing.
class Views::Admin::SettingsPassword < Views::Base
  def initialize(form:, wrong:)
    @form = form
    @wrong = wrong
  end

  def view_template
    render Components::Panel.new(title: t("admin.password_check.title")) do
      render Views::Admin::PasswordCheck.new(form: @form, wrong: @wrong, required: false,
                                             why: t("admin.password_check.why_settings", minutes: ::Admin::Sudo::FOR.in_minutes.to_i))
    end
  end
end
