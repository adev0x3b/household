# frozen_string_literal: true

require "test_helper"

# The press behind a reminder mail's link: every one of the person's
# reminders back to the bell alone.
class Reminders::StopEmailTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @mailed = [ events(:groceries), events(:methotrexate) ].map { _1.event_reminders.create!(profile: @alice, offset_minutes: 60, by_email: true) }
    @bobs = events(:groceries).event_reminders.create!(profile: profiles(:bob), offset_minutes: 60, by_email: true)
  end

  test "stops every one of the person's reminders by email, and no one else's, and tells their bell" do
    assert_equal 2, Reminders::StopEmail.call(@alice)

    assert_equal([ false, false ], @mailed.map { _1.reload.by_email? })
    assert_predicate @bobs.reload, :by_email?
    assert_equal [ "reminder_mails_stopped" ], @alice.notifications.pluck(:kind)
  end

  test "with none to stop, the bell hears nothing" do
    Reminders::StopEmail.call(@alice)

    assert_equal 0, Reminders::StopEmail.call(@alice)
    assert_equal 1, @alice.notifications.count
  end
end
