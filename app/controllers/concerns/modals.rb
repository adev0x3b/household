# frozen_string_literal: true

# A form or a question opens as a modal in the layout's "modals" frame, and
# is answered there without leaving the page. These name the moves a
# controller makes with it: opening one at its address, opening one as the
# answer to a press, drawing it again, and closing it.
#
#   render_modal(Views::Recipes::Modals::Form.new(…), page: recipes_path)
#   render turbo_stream: open_modal(Views::Admin::Modals::Password.new(…))
#   render turbo_stream: redraw_modal(form), status: :unprocessable_content
#   render turbo_stream: [ close_modal, toast(:notice, t("books.lookup.already_there", title: book.title)) ]
module Modals
  extend ActiveSupport::Concern

  FRAME = "modals"

  private

  # A modal at its own address, which can also be opened as a page: in a new
  # tab, or after signing in again, when Devise returns to the address that
  # asked for it. A page can't show a modal's stream, so it goes to `page`,
  # where the modal belongs. The stream comes first, so a request that
  # accepts anything still gets it.
  def render_modal(view, page:)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: open_modal(view) }
      format.html { redirect_to page }
    end
  end

  # In place of whatever is open: one modal at a time, since a modal over a
  # modal loses the first when the second closes them both. A modal that
  # needs another opened from it is a page instead (a purchase history).
  def open_modal(view) = turbo_stream.update(FRAME, view)

  # What is open, drawn again: with its errors, or at its next step.
  def redraw_modal(view) = turbo_stream.update(FRAME, view)

  # Every modal gone, once what was asked is done.
  def close_modal = turbo_stream.update(FRAME, "")
end
