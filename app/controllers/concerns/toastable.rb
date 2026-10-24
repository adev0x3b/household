# frozen_string_literal: true

# A toast as a controller's answer. `toast` is a Turbo Stream action, to
# render alone or beside others; before a redirect, `toast_flash` puts the
# same words in the flash and the next page shows them as a toast.
#
#   render turbo_stream: toast(:alert, t("books.lookup.invalid_isbn"))
#
#   toast_flash(:success, t("recipes.notices.destroyed"))
#   redirect_to recipes_path, status: :see_other
module Toastable
  extend ActiveSupport::Concern

  private

  # A Turbo Stream action that adds a toast to the layout's toasts, alone or
  # inside `render turbo_stream: [...]`. `body` and `detail` are text
  # (escaped); a link goes in as a SafeBuffer from a helper.
  def toast(kind, body, detail: nil)
    turbo_stream.append(
      Components::Toast::CONTAINER_ID,
      html: render_to_string(Components::Toast.new(kind: kind, body: body, detail: detail), layout: false)
    )
  end

  # Sets flash so the toast renders on the next full page load (redirect).
  # The flash travels in the session as a plain string, so it is always text.
  def toast_flash(kind, body)
    flash[kind] = body
  end
end
