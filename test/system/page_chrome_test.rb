# frozen_string_literal: true

require "application_system_test_case"

# What surrounds every page, by keyboard alone: a way past it to the page's
# content, a top bar whose controls take the focus in the order they are
# seen, and a navigation drawer that takes the focus only while it is open.
class PageChromeTest < ApplicationSystemTestCase
  setup do
    sign_in profiles(:alice)
  end

  test "the first press of Tab offers to skip to the content, and Enter lands there" do
    visit books_path

    press(:tab)
    assert_focused find_link(I18n.t("navbar.skip_to_content"))
    assert_accessible "the skip link, shown"

    press(:enter)
    assert_focused find("main#content")
    press(:tab)
    assert_focus_within "main#content"
  end

  test "the top bar is the page's banner, and its controls take the focus from left to right" do
    visit books_path
    assert_selector "header.navbar-topbar"
    5.times { press(:tab) unless in_top_bar? }

    lefts = []
    while in_top_bar?
      lefts << page.evaluate_script("document.activeElement.getBoundingClientRect().left")
      press(:tab)
    end

    assert_operator lefts.size, :>=, 3
    assert_equal lefts.sort, lefts
  end

  test "a page for someone signed out has its content in main too" do
    sign_out :profile
    visit new_profile_session_path

    assert_selector "main#content form"
  end

  test "the closed drawer and its links are never reached by Tab" do
    visit books_path

    15.times do
      press(:tab)
      refute_focus_in_drawer
    end
  end

  test "Menu on a phone puts the focus on the drawer's first link, keeps it there, and Escape gives it back" do
    visit books_path
    menu = find_button(I18n.t("navbar.menu"))
    press_tab_until menu
    press(:enter)

    assert_focused find("#navbar-sheet").find_link(I18n.t("navbar.links.home"))
    40.times do
      press(:tab)
      assert_focus_kept_in_drawer
    end

    press(:escape)
    assert_focused menu
  end

  test "a folded group's links are reached only once it is unfolded" do
    visit books_path
    press_tab_until find_button(I18n.t("navbar.menu"))
    press(:enter)
    collections = find("#navbar-group-agenda", visible: :all).find_link(I18n.t("navbar.links.collections"), visible: :all)

    40.times do
      press(:tab)
      refute focused?(collections), "a folded link took the focus"
    end

    unfold = find_button(I18n.t("navbar.groups.expand", group: I18n.t("navbar.groups.agenda")))
    press_tab_until unfold
    press(:enter)
    press(:tab)
    assert_focused collections
  end

  test "from a tablet up the burger opens the panel with the focus inside, and the bar under it is out of reach" do
    page.current_window.resize_to(1280, 900)
    visit books_path
    press_tab_until find_button(I18n.t("navbar.menu"))
    press(:enter)

    assert_focus_within "#navbar-sheet"
    40.times do
      press(:tab)
      assert_focus_kept_in_drawer
    end
  ensure
    page.current_window.resize_to(390, 844)
  end

  private

  def refute_focus_in_drawer
    inside = page.evaluate_script("document.getElementById('navbar-sheet').contains(document.activeElement)")
    refute inside, "the closed drawer took the focus, on #{page.active_element.text.squish}"
  end

  # Past the drawer's last link, Chrome moves the focus to its own controls
  # (the page sees it on body) before coming back to the first.
  def assert_focus_kept_in_drawer
    kept = page.evaluate_script(<<~JS)
      document.activeElement === document.body || document.getElementById("navbar-sheet").contains(document.activeElement)
    JS
    assert kept, "the focus left the open drawer for #{page.active_element.text.squish}"
  end

  def in_top_bar?
    page.evaluate_script("document.activeElement.closest('.navbar-topbar') !== null")
  end
end
