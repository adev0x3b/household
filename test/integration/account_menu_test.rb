# frozen_string_literal: true

require "test_helper"

# The account menu behind the avatar: who's signed in, their Household
# page, "This device", the language, and Log out last. The drawer keeps
# none of it.
class AccountMenuTest < ActionDispatch::IntegrationTest
  test "the avatar drops who's signed in, the Household page, this device, the language and, last, Log out" do
    member = profiles(:bob)
    sign_in member

    get root_path
    assert_select ".navbar-topbar .account-menu__button:not([aria-haspopup])[aria-expanded=false][aria-controls=account-menu-panel][data-dropdown-target=toggler]"
    assert_select "#account-menu-panel" do
      assert_select ".account-menu__name", text: "Bob Example"
      assert_select ".account-menu__household", text: member.household.name
      assert_select "a.account-menu__link:not(.is-current)[href='#{household_path}']", text: /Household/
      assert_select ".navbar-device .navbar-device__title", text: I18n.t("pwa.device.title")
      assert_select ".account-menu__locale form", 2
      assert_select ".account-menu__locale span[lang=en]", text: "English"
      assert_select ".account-menu__locale span[lang=it]", text: "Italiano"
      assert_select ".account-menu__group:last-child form[action='#{destroy_profile_session_path}'][data-turbo=false] .account-menu__logout"
    end
    assert_select ".navbar-sheet form", 0
    assert_select ".navbar-sheet .navbar-device", 0
    assert_select ".navbar-sheet a[href='#{household_path}']", 0

    get household_path
    assert_select "a.account-menu__link.is-current[aria-current=page][href='#{household_path}']"
  end

  test "on the demo, the device's push line says it isn't set up here" do
    demo_household
    on_the_demo do
      post demo_path, params: { as: "alex.demo" }
      follow_redirect!

      assert_select "#account-menu-panel .navbar-device__status", text: I18n.t("push.unavailable.not_configured")
      assert_select "#account-menu-panel .account-menu__name", text: "Alex"
    end
  end
end
