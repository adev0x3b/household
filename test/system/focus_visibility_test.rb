# frozen_string_literal: true

require "application_system_test_case"

# Where the focus is can always be seen: every control shows a change when
# it takes it, and the browser never scrolls the focused one under the
# fixed top bar or the phone's bottom bar.
class FocusVisibilityTest < ApplicationSystemTestCase
  setup { sign_in profiles(:alice) }

  test "tabbing down the calendar on a phone never leaves the focus under a fixed bar" do
    visit calendar_path

    60.times do
      press(:tab)
      assert_focus_in_sight if page.evaluate_script("document.activeElement.closest('main') !== null")
    end
  end

  test "the top bar's search shows that it has the focus" do
    visit books_path
    search = find(".index-search")
    resting = ring_of(search)

    press_tab_until find(".index-search__input")

    assert_not_equal resting, ring_of(search), "the search looks the same with the focus as without"
  end

  test "the uploader's drop zone shows that its file field has the focus" do
    visit uploads_path
    click_on I18n.t("uploads.index.new")
    drop = find(".uploader__drop")
    resting = ring_of(drop)

    press_tab_until find(".uploader__input", visible: :all)

    assert_not_equal resting, ring_of(drop), "the drop zone looks the same with the focus as without"
  end

  private

  # The focused element's middle is not covered by anything drawn over it,
  # such as the top bar or the bottom bar.
  def assert_focus_in_sight
    covered_by = page.evaluate_script(<<~JS)
      (() => {
        const focused = document.activeElement
        const box = focused.getBoundingClientRect()
        const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
        return top && (focused.contains(top) || top.contains(focused)) ? null : (top?.className || "nothing on screen")
      })()
    JS
    assert_nil covered_by, "the focused #{page.active_element.tag_name} is under #{covered_by}"
  end

  # What a focus ring is drawn with: the outline, the shadow and the border.
  def ring_of(element)
    element.evaluate_script(<<~JS)
      (() => {
        const style = getComputedStyle(this)
        return [style.outlineStyle, style.outlineColor, style.boxShadow, style.borderColor].join(" | ")
      })()
    JS
  end
end
