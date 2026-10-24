# frozen_string_literal: true

require "application_system_test_case"

# The calendar is where everything is planned and done: a day's "+" adds
# any kind, its card ticks it.
class CalendarTest < ApplicationSystemTestCase
  setup do
    sign_in profiles(:alice)
    @today = Date.current
  end

  test "a task added from a day's + is on its card, and ticking it marks it done" do
    visit calendar_path

    within("#day_#{@today.iso8601}") { click_on I18n.t("calendar.day_card.add_event_on", date: I18n.l(@today, format: :day_long)) }
    assert_accessible "the menu of every kind, open"
    within("#day_add_menu") { click_on I18n.t("calendar.day_card.event_types.task") }
    within(".modal") do
      fill_in "task[title]", with: "Repot the basil"
      assert_accessible "the new task's form"
      click_on I18n.t("tasks.form.create")
    end

    within("#day_#{@today.iso8601}") do
      assert_text "Repot the basil"
      click_on I18n.t("calendar.day_card.complete", title: "Repot the basil")
      assert_selector "[aria-label='#{I18n.t("calendar.day_card.reopen", title: "Repot the basil")}']"
    end
    assert_text I18n.t("tasks.notices.completed") # the card turns at once; the toast is the server's answer
    assert_predicate profiles(:alice).events.find_by!(title: "Repot the basil").first_occurrence, :completed?
    assert_accessible "the day with its task done"
  end

  test "a card's more deletes one day of a repeating series, after asking, and offers only the day for a series that doesn't repeat" do
    weekly_event(profile: profiles(:alice), type: "Task", starts_on: Date.new(2027, 3, 1), title: "Bins")
    task!(profile: profiles(:alice), date: Date.new(2027, 3, 9), title: "Call the plumber")
    visit calendar_path(month: 3, year: 2027)
    assert_eventually("the calendar listens to its month", within: 5) { CalendarWatch.months_for(profiles(:alice).id).include?("2027-03") }

    within("#day_2027-03-09 .task-card", text: "Call the plumber") { click_on I18n.t("links.cards.more") }
    within("#card_menu") do
      assert_button I18n.t("links.cards.delete_occurrence")
      assert_no_button I18n.t("links.cards.delete_series")
    end
    page.active_element.send_keys(:escape)
    assert_no_selector "#card_menu", visible: true

    within("#day_2027-03-08 .task-card", text: "Bins") { click_on I18n.t("links.cards.more") }
    assert_accessible "a card's menu, open"
    within("#card_menu") do
      assert_button I18n.t("links.cards.delete_series")
      click_on I18n.t("links.cards.delete_occurrence")
    end
    within("dialog#confirm_dialog[open]") do
      assert_text I18n.t("links.cards.delete_occurrence_confirm")
      click_on I18n.t("links.cards.delete_occurrence")
    end

    within("#day_2027-03-08") { assert_no_text "Bins" }
    within("#day_2027-03-15") { assert_text "Bins" }
  end

  test "a change to one day stays on it; a change to the whole series reaches every day not changed on its own" do
    weekly_event(profile: profiles(:alice), type: "Task", starts_on: Date.new(2027, 3, 1), title: "Bins")
    visit calendar_path(month: 3, year: 2027)

    edit_day("2027-03-08", from: "Bins", to: "Bins and glass", apply_to: "day")
    within("#day_2027-03-08") { assert_text "Bins and glass" }
    within("#day_2027-03-15") { assert_no_text "glass" }

    edit_day("2027-03-15", from: "Bins", to: "Recycling", apply_to: "series")
    within("#day_2027-03-22") { assert_text "Recycling" }
    within("#day_2027-03-01") { assert_text "Recycling" }
    within("#day_2027-03-08") { assert_text "Bins and glass" } # the day changed on its own keeps its change
  end

  test "a housemate's change that redraws the calendar leaves an open form as the reader left it" do
    alice, bob = profiles(:alice), profiles(:bob)
    link = Link.create!(requester: alice, addressee: bob)
    task!(profile: alice, date: @today, title: "Water the ferns")
    task!(profile: bob, date: @today, title: "Fix the gate")
    visit calendar_path
    assert_eventually("the calendar listens to its month", within: 5) do
      CalendarWatch.months_for(alice.id).include?(@today.strftime("%Y-%m"))
    end

    within("#day_#{@today.iso8601}") { find("a[class$='__title-link']", exact_text: "Water the ferns").click }
    within(".modal") { fill_in "task[title]", with: "Water the ferns and the basil" }

    Links::Accept.call(link) # Bob says yes: Alice's months are drawn again, with his tasks

    within("#day_#{@today.iso8601}") { assert_text "Fix the gate" }
    within(".modal") do
      assert_field "task[title]", with: "Water the ferns and the basil"
      find(".modal__btn--primary").click
    end
    assert_no_selector ".modal"
    assert_text I18n.t("tasks.notices.updated")
    within("#day_#{@today.iso8601}") { assert_text "Water the ferns and the basil" }
  end

  test "the month picker steps by arrow key without loading a page for each step, and goes on Enter" do
    visit calendar_path(month: 3, year: 2027)
    month = find_field(I18n.t("calendar.navigation.month"))
    # Turbo keeps the window from one page to the next, so what it counts
    # here counts every page asked for.
    page.execute_script("window.fetched = 0; addEventListener('turbo:before-fetch-request', () => window.fetched++)")
    month.execute_script("this.focus()")

    press(:arrow_down)
    press(:arrow_down)
    assert_equal "5", month.value
    press(:enter)

    assert_selector "#day_2027-05-31"
    assert_equal 1, page.evaluate_script("window.fetched"), "one page for two steps"
  end

  private

  def edit_day(date, from:, to:, apply_to:)
    within("#day_#{date}") { find("a[class$='__title-link']", exact_text: from).click }
    within(".modal") do
      fill_in "task[title]", with: to
      select I18n.t("form.apply_to.#{apply_to}"), from: I18n.t("form.apply_to.label")
      assert_accessible "a day of a series, being edited"
      find(".modal__btn--primary").click
    end
    assert_no_selector ".modal"
  end
end
