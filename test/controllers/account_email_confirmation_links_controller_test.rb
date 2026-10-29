# frozen_string_literal: true

require "test_helper"

# The link that confirms an address, mailed again from the Account page.
class AccountEmailConfirmationLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  def press = post(account_email_confirmation_link_path, headers: submitted_from(account_path))

  test "queues the link and says it is on its way" do
    with_relay { press }

    assert_redirected_to account_path
    assert_equal "email_confirmation", OutgoingEmail.sole.kind
    follow_redirect!
    assert_toast "A link to confirm alice@example.com is on its way."
  end

  test "refused where it stands when it can't go: no mail, the day's links used, or nothing to confirm" do
    press
    assert_response :unprocessable_content
    assert_toast "Household sends no mail here."

    with_relay do
      3.times { Emails::Enqueue.call(@alice, :email_confirmation) }
      press
      assert_toast "You've had 3 links to confirm an address today: ask again tomorrow."

      @alice.update!(email_confirmed_at: Time.current)
      press
      assert_toast "Your address is confirmed already."
    end
    assert_equal 3, OutgoingEmail.count
  end
end
