# frozen_string_literal: true

# What the admin does to someone else's account (a link to set its
# password, removing it) waits for their password again (Admin::Sudo). The
# press is answered with a modal that asks for it and sends the same press
# again, with the password; a wrong one draws the modal again. A member,
# and an admin who typed it lately, go straight on.
#
#   return unless admin_password_given?(subtitle: t("…", name: member.display_name), submit: t("…"))
module ReauthenticatesAdmin
  extend ActiveSupport::Concern

  private

  # True when the press may go on; otherwise the modal is the answer.
  def admin_password_given?(subtitle:, submit:, danger: false)
    return true if Admin::Sudo.new(session, current_profile).passed?(params[:password])

    wrong = params.key?(:password)
    modal = Views::Admin::Modals::Password.new(url: request.path, method: request.request_method.downcase,
                                               subtitle: subtitle, submit: submit, danger: danger, wrong: wrong)
    render turbo_stream: (wrong ? redraw_modal(modal) : open_modal(modal)), status: (wrong ? :unprocessable_content : :ok)
    false
  end
end
