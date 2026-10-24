# frozen_string_literal: true

require "application_system_test_case"

# "Needs attention" on home is acted on where it is read: an item opens its
# day's form in place, and a dose that went unrecorded is settled with one
# press. Either way home draws itself again without it, and the reader
# never leaves.
class NeedsAttentionTest < ApplicationSystemTestCase
  setup do
    @carol = profiles(:carol) # keeps nothing else, so her list holds only what is made here
    sign_in @carol
  end

  test "an overdue task is done from its form, and a missed dose is marked skipped, without leaving home" do
    task!(profile: @carol, date: Date.current - 3, title: "Renew the passport")
    medication!(profile: @carol, date: Date.current - 2, name: "Vitamin D")
    visit root_path

    within(".stat-attention") do
      assert_selector ".stat-attention__item", count: 2
      find(".stat-attention__link", text: "Renew the passport").click
    end
    within(".modal") do
      select I18n.t("tasks.status.completed"), from: I18n.t("tasks.form.status_label")
      click_on I18n.t("tasks.form.update")
    end
    assert_text I18n.t("tasks.notices.updated")
    within(".stat-attention") { assert_no_text "Renew the passport" }

    within(".stat-attention") { click_on I18n.t("statistics.attention.resolve", subject: "Vitamin D") }
    assert_text I18n.t("statistics.attention.notices.resolved")
    assert_no_selector ".stat-attention" # nothing left: the list is gone, not shown empty
    assert_current_path root_path
    assert_accessible "home, with nothing needing attention"
  end
end
