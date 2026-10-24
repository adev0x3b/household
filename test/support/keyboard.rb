# frozen_string_literal: true

# A system test that drives the page by keyboard alone, as someone who
# can't use a pointer does: keys go to whatever has the focus, and the test
# asks where the focus is, never clicks.
module Keyboard
  # Presses a key where the focus is. Capybara's send_keys goes through an
  # element, which takes the focus again first, and so would start a date
  # field over at its first part on every press.
  def press(*keys)
    page.driver.browser.action.send_keys(*keys).perform
  end

  # Goes back one stop. Shift is held down around Tab, which a single
  # send_keys of both would press one after the other.
  def press_shift_tab
    page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
  end

  # Presses Tab until `element` has the focus, failing after `within` presses.
  def press_tab_until(element, within: 60)
    within.times do
      return if focused?(element)

      press :tab
    end
    flunk "#{element.text.squish.presence || element.tag_name} not reached in #{within} presses of Tab"
  end

  # Waits, as Capybara's own assertions do, since the focus often moves after
  # an answer arrives. An element with an id counts as focused when whatever
  # now carries that id is: a live redraw may draw it again in its place.
  def assert_focused(element, message = nil)
    id = element[:id].presence
    page.document.synchronize { raise Capybara::ExpectationNotMet unless focused?(element, id) }
    pass
  rescue Capybara::ExpectationNotMet
    expected = id ? "##{id}" : describe(element)
    flunk message || "expected the focus on #{expected}, found it on #{describe(page.active_element)}"
  end

  # The focus is inside the element `selector` names.
  def assert_focus_within(selector, message = nil)
    inside = page.evaluate_script("document.querySelector(arguments[0])?.contains(document.activeElement)", selector)
    assert inside, message || "expected the focus inside #{selector}, found it on #{describe(page.active_element)}"
  end

  private

  def focused?(element, id = element[:id].presence)
    id ? page.evaluate_script("document.activeElement.id") == id : page.active_element == element
  end

  def describe(element)
    return "the page itself" if element.tag_name == "body"

    words = element.text.squish.presence || element[:"aria-label"] || element[:id]
    [ element.tag_name, words ].compact.join(" ")
  end
end
