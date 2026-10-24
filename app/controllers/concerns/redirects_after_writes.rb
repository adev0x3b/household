# frozen_string_literal: true

# A write that succeeds answers with a visit, with its toast in the flash.
# When the visit is to the page the person is on, Turbo morphs it in place
# and keeps their scroll and their search, and the modal the save came
# from closes with it. Every part of the page is drawn again from the
# records, so a title, an order, a count or an empty list can't be left
# stale by a stream the controller forgot. A form with errors still comes
# back in its modal (Modals#redraw_modal).
#
#   redirect_back_after_save(recipe_path(@recipe), notice: t("recipes.notices.updated"))
#   redirect_after_destroy(recipe_path(@recipe), list: recipes_path, notice: t("recipes.notices.destroyed"))
module RedirectsAfterWrites
  extend ActiveSupport::Concern

  private

  # Back to the page the save was made on, or to `fallback` when the
  # browser didn't say which page that was.
  def redirect_back_after_save(fallback, notice:)
    toast_flash(:success, notice)
    redirect_back_or_to fallback, status: :see_other
  end

  # Back as well, unless that page was the deleted record's own: there is
  # nothing left to show there, so the person goes to `list`.
  def redirect_after_destroy(record_path, list:, notice:)
    toast_flash(:success, notice)
    back = url_from(request.referer)
    back = nil if back && URI(back).path == record_path
    redirect_to back || list, status: :see_other
  end
end
