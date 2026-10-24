# frozen_string_literal: true

require "application_system_test_case"

# The household's owner removes someone from its page, after the app's own
# confirmation: everything they kept goes with them, and they are signed
# out wherever they were.
class RemovingAHousemateTest < ApplicationSystemTestCase
  test "the owner removes a housemate, who is gone from the household and signed out" do
    alice, carol = profiles(:alice), profiles(:carol)
    using_session(:carol) do
      sign_in carol
      visit root_path
    end

    sign_in alice
    visit household_path
    within(".household__row", text: carol.full_name) { click_on I18n.t("households.people.remove") }
    within("dialog#confirm_dialog[open]") do
      assert_text I18n.t("households.people.remove_confirm", name: carol.display_name)
      click_on I18n.t("households.people.remove")
    end

    assert_text I18n.t("households.notices.removed", name: carol.display_name)
    assert_no_selector ".household__row", text: carol.full_name
    assert_not Profile.exists?(carol.id)
    assert_accessible "the household, one person fewer"

    using_session(:carol) do
      visit root_path
      assert_text I18n.t("sessions.new.title")
    end
  end
end
