# frozen_string_literal: true

require "test_helper"

# The reminders mailed to a person: to their address, marked as the app's
# own, with the link that stops them in its foot and in the header a mail
# client offers in one click.
class RemindersMailerTest < ActionMailer::TestCase
  setup do
    @alice = profiles(:alice)
    @alice.update!(time_zone: "Europe/Rome", email_confirmed_at: 1.day.ago)
    @rent = series!("Task", profile: @alice, starts_on: Date.new(2026, 10, 31), title: "Pay the rent")
  end

  test "goes to the person, from the app, marked so nothing answers it automatically, and leads to the day on the calendar" do
    mail = reminders_mail

    assert_equal [ "alice@example.com" ], mail.to
    assert_equal "Household <household@household.example>", mail[:from].to_s
    assert_equal "auto-generated", mail["Auto-Submitted"].to_s
    assert_equal "A reminder from Household", mail.subject
    assert_includes mail.text_part.body.to_s, "This is your reminder for your task “Pay the rent” on Saturday 31 October."
    assert_includes mail.text_part.body.to_s, "Open it in Household:\nhttp://example.com/calendar?month=10&year=2026#day_2026-10-31"
  end

  test "its link stops every reminder by email, from the foot or the header a mail client presses in one click" do
    mail = reminders_mail

    link = mail["List-Unsubscribe"].to_s[/\A<(.+)>\z/, 1]
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
    assert link.start_with?("http://example.com/email_unsubscription?token="), link
    assert_equal @alice, Profile.find_by_token_for(:email_unsubscription, Rack::Utils.parse_query(URI(link).query)["token"])
    assert_includes mail.text_part.body.to_s, "Stop every reminder by email:\n#{link}"
    assert_select_in(mail.html_part.body.to_s, "a[href=?]", link, text: "Stop every reminder by email")
  end

  private

  def reminders_mail
    day = @rent.occurrence_on(Date.new(2026, 10, 31), time: nil)
    due = Reminders::StillDue::Reminder.new(row: nil, occurrence: day, due_at: @alice.zone.local(2026, 10, 31, 9), timed: false)
    with_relay { @alice.as_viewer { RemindersMailer.with(profile: @alice, reminders: [ due ]).reminders.message } }
  end

  def assert_select_in(html, ...) = assert_select(Nokogiri::HTML5(html), ...)
end
