# frozen_string_literal: true

require "application_system_test_case"

# Two housemates who see each other's calendars: what one asks to do with
# the other's day waits for her OK, and is done when she gives it.
class LinkedHousematesTest < ApplicationSystemTestCase
  test "a linked housemate's tick waits for the owner, who approves it from her bell" do
    alice, bob = profiles(:alice), profiles(:bob)
    link!(alice, bob) # Alice's tasks: read on, the rest asked
    day = task!(profile: alice, date: Date.current, title: "Water the ferns")

    sign_in bob
    visit calendar_path
    within("#day_#{Date.current.iso8601}") { click_on I18n.t("calendar.day_card.complete", title: "Water the ferns") }
    assert_text I18n.t("links.notices.asked", name: alice.display_name)
    assert_predicate day.reload, :pending?, "nothing is done until she says so"

    using_session(:alice) do
      sign_in alice
      visit root_path
      click_on I18n.t("notifications.title")
      assert_accessible "the bell, open, with a request"
      within(".notifications__panel") { click_on I18n.t("notifications.actions.approve") }
      assert_no_selector ".notifications__actions"
    end

    assert_predicate day.reload, :completed?, "approved, it is done as hers"
  end

  test "deleting a linked housemate's day from its card is worded as asking her" do
    alice, bob = profiles(:alice), profiles(:bob)
    link!(alice, bob) # deleting her tasks is asked too
    task!(profile: alice, date: Date.current, title: "Water the ferns")

    sign_in bob
    visit calendar_path
    within("#day_#{Date.current.iso8601} .task-card", text: "Water the ferns") { click_on I18n.t("links.cards.more") }
    within("#card_menu") { click_on I18n.t("links.cards.ask_delete_occurrence", name: alice.display_name) }
    within("dialog#confirm_dialog[open]") do
      assert_text I18n.t("links.cards.ask_delete_occurrence_confirm", name: alice.display_name)
      click_on I18n.t("links.cards.ask_delete_occurrence", name: alice.display_name)
    end

    assert_text I18n.t("links.notices.asked", name: alice.display_name)
    assert_predicate LinkApproval.last, :pending?
  end
end
