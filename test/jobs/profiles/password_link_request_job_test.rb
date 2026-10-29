# frozen_string_literal: true

require "test_helper"

# "Forgot your password?" decided away from the request: by id, or not at
# all when the typed login found nobody.
class Profiles::PasswordLinkRequestJobTest < ActiveJob::TestCase
  test "asks for a link for whoever the login found, and does nothing for nobody" do
    alice = profiles(:alice).tap { _1.update!(email_confirmed_at: 1.day.ago) }

    with_relay do
      Profiles::PasswordLinkRequestJob.perform_now(nil)
      Profiles::PasswordLinkRequestJob.perform_now(0)
      assert_empty OutgoingEmail.all

      Profiles::PasswordLinkRequestJob.perform_now(alice.id)
    end
    assert_equal [ alice.id ], OutgoingEmail.password_link.pluck(:profile_id)
  end
end
