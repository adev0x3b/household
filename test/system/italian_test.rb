# frozen_string_literal: true

require "application_system_test_case"

# Someone who reads Italian has the whole app in it: the page's language,
# its words, its dates, and what the server answers to a press.
class ItalianTest < ApplicationSystemTestCase
  setup do
    @alice = profiles(:alice)
    @alice.update!(locale: "it")
    sign_in @alice
  end

  test "a task is added and done on the calendar in Italian, with Italian dates and answers" do
    visit calendar_path(month: 3, year: 2027)
    assert_selector "html[lang=it]"

    I18n.with_locale(:it) do
      assert_select I18n.t("calendar.navigation.month"), selected: "Marzo" # standing alone, it takes a capital
      add_to_day(Date.new(2027, 3, 1), :task)
      within(".modal") do
        assert_text I18n.t("tasks.form.new_title")
        fill_in "task[title]", with: "Rinnovare il passaporto"
        click_on I18n.t("tasks.form.create")
      end
      assert_text I18n.t("tasks.notices.created")

      within_day(Date.new(2027, 3, 1)) do
        assert_selector ".day-card__day-name", text: /\A#{I18n.l(Date.new(2027, 3, 1), format: :weekday)}\z/i # "lun", in capitals
        click_on I18n.t("calendar.day_card.complete", title: "Rinnovare il passaporto")
      end
      assert_text I18n.t("tasks.notices.completed")
    end
    assert_accessible "the calendar in Italian, a task done"
  end
end
