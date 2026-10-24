# frozen_string_literal: true

require "application_system_test_case"

# A series made to repeat with the form's fields: the interval and the days
# of the week show once it repeats weekly (recurrence_fields_controller.js),
# and the rule they make puts the series on those days only.
class RepeatingSeriesTest < ApplicationSystemTestCase
  test "a task every other week on Monday and Thursday is on those days, and on no other" do
    sign_in profiles(:alice)
    visit calendar_path(month: 3, year: 2027)

    add_to_day(Date.new(2027, 3, 1), :task) # a Monday
    within(".modal") do
      fill_in "task[title]", with: "Piano lesson"
      assert_no_field I18n.t("event_fields.interval_label") # not repeating, nothing to say how often
      select I18n.t("event_fields.frequencies.weekly"), from: I18n.t("event_fields.frequency_label")
      fill_in I18n.t("event_fields.interval_label"), with: "2"
      check day_name(:monday), allow_label_click: true # the box is hidden; its pill is what is pressed
      check day_name(:thursday), allow_label_click: true
      assert_accessible "a new task's form, repeating weekly"
      click_on I18n.t("tasks.form.create")
    end
    assert_text I18n.t("tasks.notices.created")

    within_day(Date.new(2027, 3, 29)) { assert_text "Piano lesson" } # the month is drawn again with the series on it
    lessons = (1..31).select { |day| within_day(Date.new(2027, 3, day)) { has_text?("Piano lesson", wait: false) } }
    assert_equal [ 1, 4, 15, 18, 29 ], lessons
  end

  private

  def day_name(day) = I18n.t("date.abbr_day_names").fetch(Date::DAYNAMES.index(day.to_s.capitalize))
end
