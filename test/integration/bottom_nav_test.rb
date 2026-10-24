# frozen_string_literal: true

require "test_helper"

# The phone's bottom bar: Home, Calendar, Assistant, Messages with its
# unread count, and Menu — which opens the drawer and counts what waits for
# an answer on Links. The page you're on is marked.
class BottomNavTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @bob
  end

  test "five tabs: the everyday pages with their counts, and Menu opening the drawer" do
    send_message(Conversation.direct_between(@alice, @bob), @alice, "see you at 8")
    Link.create!(requester: @alice, addressee: @bob)

    get root_path
    assert_select "nav.bottom-nav[aria-label]" do
      assert_select ".bottom-nav__item", 5
      assert_select "a.bottom-nav__item.is-current[aria-current=page][href='#{root_path}']", text: /Home/
      assert_select "a.bottom-nav__item:not(.is-current)[href='#{calendar_path}']", text: /Calendar/
      assert_select "a.bottom-nav__item.section--assistant[href='#{assistant_path}']", text: /Assistant/
      assert_select "a.bottom-nav__item.section--messages[href='#{conversations_path}'] .messages-badge:not([hidden]) [aria-hidden]", text: "1"
      assert_select "button.bottom-nav__menu[aria-expanded=false][aria-controls=navbar-sheet][data-navbar-target=toggler]", text: /Menu/
      assert_select "button.bottom-nav__menu .links-badge:not([hidden]) [aria-hidden]", text: "1"
    end
    assert_select "main.app-content[data-navbar-target=behind]"

    get conversations_path
    assert_select "a.bottom-nav__item.is-current[href='#{conversations_path}']"
    assert_select "a.bottom-nav__item:not(.is-current)[href='#{root_path}']"
  end

  test "with nothing waiting the counts are hidden" do
    get calendar_path
    assert_select ".bottom-nav .messages-badge[hidden]"
    assert_select ".bottom-nav__menu .links-badge[hidden]"
    assert_select "a.bottom-nav__item.is-current[href='#{calendar_path}']"
  end
end
