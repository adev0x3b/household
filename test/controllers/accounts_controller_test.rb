# frozen_string_literal: true

require "test_helper"

# /account: one's own address and password, each change asking for the
# password in use. Open accounts have none to manage.
class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "the address, whether it's confirmed, and the two forms; the account menu leads here" do
    with_relay { get account_path }

    assert_response :success
    assert_select "h1", text: "Account"
    assert_select ".account__address", text: /alice@example\.com/
    assert_select ".account__address .status-badge", text: "Not confirmed"
    assert_select "form[action=?] button", account_email_confirmation_link_path, text: "Mail me a link to confirm it"
    assert_select "form[action=?] input[type=email][name=?]", account_email_change_path, "email_change[email]"
    assert_select "form[action=?] input[type=password][name=?]", account_password_path, "password_change[current_password]"
    assert_select ".account-menu a[href=?][aria-current=page]", account_path
  end

  test "a confirmed address, and one waiting for its link" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@new.example")
    @alice.email_confirmation_token!

    with_relay { get account_path }

    assert_select ".account__address .status-badge", text: "Confirmed"
    assert_select ".notice", text: /alice@new\.example is waiting to be confirmed/
    assert_select ".notice", text: /A link went out on/
    assert_select "form[action=?] button", account_email_confirmation_link_path, text: "Mail the link again"
    assert_select "form[action=?] input[name=_method][value=delete]", account_email_change_path
  end

  test "a link whose mail still waits is on its way, though a try that didn't go out left one in place" do
    @alice.update!(email_confirmed_at: 1.day.ago, unconfirmed_email: "alice@new.example")
    @alice.email_confirmation_token!
    Emails::Enqueue.call(@alice, :email_confirmation)

    with_relay { get account_path }

    assert_select ".notice", text: /A link is on its way/
    assert_select ".notice", text: /A link went out on/, count: 0
  end

  test "a confirmed address is told what comes to it: no link for a lost password to the admin, no reminders where none are allowed" do
    @alice.update!(email_confirmed_at: 1.day.ago)

    assert_equal "Household mails your reminders here and, if you ever forget your password, a link to set a new one.", address_hint
    assert_equal "If you ever forget your password, Household mails a link here to set a new one.", address_hint("REMINDER_MAILS_PER_DAY" => "0")

    @alice.admin!
    assert_equal "Household mails your reminders here.", address_hint
    assert_equal "Household mails you here when your password or your address changes.", address_hint("REMINDER_MAILS_PER_DAY" => "0")
  end

  test "where no mail goes out, nothing is offered to confirm" do
    get account_path

    assert_select ".account__address .status-badge", count: 0
    assert_select "form[action=?]", account_email_confirmation_link_path, count: 0
    assert_select ".panel .report-hint", text: /The new address takes over at once/
  end

  test "reminders that couldn't be mailed in the last day are counted, so the bell is counted on instead" do
    @alice.update!(email_confirmed_at: 1.day.ago)
    [ 2.hours.ago, 20.hours.ago, 2.days.ago ].each do |at|
      OutgoingEmail.create!(profile: @alice, kind: :reminder, status: :failed, not_before: at, expires_at: at, updated_at: at)
    end
    OutgoingEmail.create!(profile: @alice, kind: :test_mail, status: :failed, not_before: Time.current, expires_at: Time.current)
    OutgoingEmail.create!(profile: profiles(:bob), kind: :reminder, status: :failed, not_before: Time.current, expires_at: Time.current)

    with_relay { get account_path }
    assert_select ".notice", text: "In the last day, 2 reminders couldn't be mailed. Your bell still had them."

    get account_path
    assert_select ".notice", count: 0, text: /couldn't be mailed/
  end

  test "an open account has no Account page, nor a link to one" do
    on_the_demo do
      alex = demo_household.members.find_by!(username: "alex.demo")
      sign_in alex

      get account_path
      assert_response :redirect
      get root_path
      assert_select ".account-menu a[href=?]", account_path, count: 0
    end
  end

  private

  # What the address's panel says comes to it, the page drawn with these settings.
  def address_hint(settings = {})
    with_relay(settings) { get account_path }
    css_select(".panel .report-hint").first.text.strip
  end
end
