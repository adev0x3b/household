# frozen_string_literal: true

require "test_helper"

# Asking for another address from the Account page, and taking back one
# that waits.
class AccountEmailChangesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD, password_confirmation: PASSWORD) }
    sign_in @alice
  end

  def ask(email: "alice@new.example", current_password: PASSWORD)
    post account_email_change_path, params: { email_change: { email:, current_password: } }, headers: submitted_from(account_path)
  end

  test "where mail goes out, the new address waits for its link, and the page says one is on its way" do
    with_relay { ask }

    assert_redirected_to account_path
    assert_equal "alice@new.example", @alice.reload.unconfirmed_email
    follow_redirect!
    assert_toast "A link to confirm alice@new.example is on its way."
  end

  test "where none does, the new address takes over at once" do
    ask

    assert_equal "alice@new.example", @alice.reload.email
    follow_redirect!
    assert_toast "Your address is now alice@new.example."
  end

  test "a refused change draws the page again, with what was wrong where it was typed" do
    with_relay { ask(current_password: "a guess") }

    assert_response :unprocessable_content
    assert_form_error "Your password is wrong"
    assert_select "input[name=?][value=?]", "email_change[email]", "alice@new.example"
    assert_select "input[name=?][aria-invalid=true]", "email_change[current_password]"
    assert_nil @alice.reload.unconfirmed_email
  end

  test "a change waiting is taken back, and its link stops working" do
    @alice.update!(unconfirmed_email: "alice@new.example")
    token = @alice.email_confirmation_token!

    delete account_email_change_path, headers: submitted_from(account_path)

    assert_redirected_to account_path
    assert_nil @alice.reload.unconfirmed_email
    assert_nil Profile.with_email_confirmation_token(token)
  end

  test "the account's presses together are limited per person" do
    counting_rate_limits do
      9.times { |n| ask(email: "alice#{n}@new.example") }
      delete account_email_change_path, headers: submitted_from(account_path)
      post account_email_confirmation_link_path, headers: submitted_from(account_path)
      ask(email: "alice@last.example")
    end

    assert_response :too_many_requests
    assert_toast I18n.t("rate_limit.exceeded")
    assert_equal "alice8@new.example", @alice.reload.email
  end
end
