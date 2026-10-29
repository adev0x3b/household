# frozen_string_literal: true

require "application_system_test_case"

# A reminder asked for by email too, from a new task's form, or the line
# that says where to confirm an address first; and every reminder by email
# stopped from the link a reminder mail carries.
class RemindersByEmailTest < ApplicationSystemTestCase
  setup do
    @alice = profiles(:alice)
    @alice.update!(email_confirmed_at: 1.day.ago)
  end

  test "a new task's reminder, ticked to come by email too" do
    sign_in @alice
    with_relay do
      visit calendar_path(month: 3, year: 2027)
      add_to_day(Date.new(2027, 3, 1), :task)
      within(".modal") do
        fill_in "task[title]", with: "Pay the rent"
        click_on I18n.t("reminders.form.add")
        check I18n.t("reminders.form.by_email")
        assert_accessible "a new task's form, with a reminder by email too"
        click_on I18n.t("tasks.form.create")
      end
      assert_text I18n.t("tasks.notices.created")
    end

    assert_equal [ [ 1440, true ] ], Task.find_by!(title: "Pay the rent").event_reminders.pluck(:offset_minutes, :by_email)
  end

  test "while the address waits to be confirmed, the form offers no box and says where to confirm it" do
    @alice.update!(email_confirmed_at: nil)
    sign_in @alice
    with_relay do
      visit calendar_path(month: 3, year: 2027)
      add_to_day(Date.new(2027, 3, 1), :task)
      within(".modal") do
        click_on I18n.t("reminders.form.add")
        assert_no_field I18n.t("reminders.form.by_email")
        assert_link I18n.t("reminders.form.confirm_address"), href: account_path
        assert_accessible "a new task's form, its reminders not yet by email"
      end
    end
  end

  test "the link in a reminder mail stops every reminder by email, once its button is pressed" do
    reminder = events(:groceries).event_reminders.create!(profile: @alice, offset_minutes: 60, by_email: true)

    visit email_unsubscription_path(token: @alice.generate_token_for(:email_unsubscription))
    assert_accessible "the page a reminder mail's link opens"
    click_on I18n.t("email_unsubscriptions.show.submit")

    assert_text I18n.t("email_unsubscriptions.notices.stopped")
    assert_text I18n.t("email_unsubscriptions.show.none")
    assert_not reminder.reload.by_email?
  end
end
