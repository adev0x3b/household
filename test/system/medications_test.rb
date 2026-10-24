# frozen_string_literal: true

require "application_system_test_case"

# A medication taken at set times of the day: the form's stepper proposes
# the times, each one changed in place (dose_times_controller.js), its
# supply rows say what each dose uses (nested_fields_controller.js), and a
# dose ticked on the calendar takes that from the cupboard.
class MedicationsTest < ApplicationSystemTestCase
  setup do
    @alice = profiles(:alice)
    @tablets = Supply.create!(
      profile: @alice, name: "Ramipril 5 mg", category: :medication, unit_label: "tablets",
      supply_purchases_attributes: [ { profile: @alice, quantity_purchased: 30, purchased_on: Date.current } ]
    )
    sign_in @alice
  end

  test "a medication taken twice a day has two doses a day, and taking one draws a tablet from the stock" do
    visit calendar_path
    add_to_day(Date.current, :medication)
    within(".modal") do
      fill_in I18n.t("medications.form.name_label"), with: "Ramipril"
      select I18n.t("medications.kind.pill"), from: I18n.t("medications.form.kind_label")
      click_on I18n.t("medications.form.supply_uses.add")
      select @tablets.name, from: I18n.t("medications.form.supply_uses.supply_placeholder")
      fill_in I18n.t("medications.form.supply_uses.quantity_label"), with: "1"
      select I18n.t("event_fields.frequencies.daily"), from: I18n.t("event_fields.frequency_label")
      2.times { click_on I18n.t("medications.form.times.more") }
      assert_selector ".dose-times__count", text: "2"
      within(all(".dose-times__row").last) do
        select I18n.t("medications.anchors.CV"), from: I18n.t("medications.form.times.label")
      end
      assert_accessible "a new medication's form, with two doses a day"
      click_on I18n.t("medications.form.create")
    end
    assert_text I18n.t("medications.notices.created")

    # The first time as it was proposed, the second changed to a meal.
    morning, dinner = "08:00", I18n.t("medications.anchors.CV")
    within_day(Date.current) do
      times = all(".medication-card", text: "Ramipril").map { |dose| dose.find(".medication-card__time").text }
      assert_equal [ morning, dinner ], times
      within(dose_at(morning)) { click_on I18n.t("calendar.day_card.complete", title: "Ramipril") }
    end
    assert_text I18n.t("medications.notices.completed")
    assert_equal 29, @tablets.reload.total_remaining
    within_day(Date.current) do # the other dose of the day is still to take
      within(dose_at(dinner)) { assert_link I18n.t("calendar.day_card.complete", title: "Ramipril") }
    end

    visit supplies_path
    within("#supply_#{@tablets.id}") { assert_text "29 tablets" }
  end

  private

  def dose_at(time)
    find(".medication-card", text: "Ramipril") { _1.has_selector?(".medication-card__time", text: time, wait: false) }
  end
end
