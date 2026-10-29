# frozen_string_literal: true

require "test_helper"

# The outbox keeps sent mail for a week and what couldn't go out for a
# month, and never touches what still waits.
class Emails::SweepJobTest < ActiveSupport::TestCase
  def row(status, ended)
    at = ended.ago
    OutgoingEmail.create!(profile: profiles(:alice), kind: :test_mail, status: status, not_before: at, expires_at: at + 15.minutes, updated_at: at)
  end

  test "clears sent mail after a week, failed and dropped mail after a month, and nothing still waiting" do
    kept = [ row(:sent, 6.days), row(:failed, 29.days), row(:dropped, 29.days), row(:queued, 40.days), row(:sending, 40.days) ]
    row(:sent, 8.days)
    row(:failed, 31.days)
    row(:dropped, 31.days)

    Emails::SweepJob.perform_now

    assert_equal kept.map(&:id).sort, OutgoingEmail.ids.sort
  end
end
