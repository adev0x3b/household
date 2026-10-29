# frozen_string_literal: true

require "test_helper"

# /admin/emails: the admin sees whether mail goes out and why not, the
# budgets, what waits and what couldn't go out, and sends themselves a
# test; nobody else gets in.
class Admin::EmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = profiles(:alice).tap(&:admin!)
    sign_in @admin
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  test "a member who isn't an admin is turned away, and sees no link" do
    sign_in profiles(:bob)

    get admin_emails_path
    assert_redirected_to root_path
    with_relay { post admin_test_mail_path }
    assert_redirected_to root_path
    assert_not OutgoingEmail.exists?

    get root_path
    assert_select "a.navbar-link[href=?]", admin_emails_path, count: 0
  end

  test "with no relay set, the page says what is missing and offers no test" do
    get admin_emails_path

    assert_response :success
    assert_select "a.navbar-link[href=?]", admin_emails_path
    assert_select ".report-status--critical .status-badge", text: /Not set up/
    assert_select ".report-status__now", text: /relay has no server/
    assert_select ".emails__facts", text: /Relay\s*Not set/
    assert_select "a[href=?]", admin_test_mail_path, count: 0
  end

  test "turned off, it says so" do
    with_relay("OUTGOING_MAIL" => "off") { get admin_emails_path }

    assert_select ".report-status--neutral .status-badge", text: /Off/
    assert_select "a[href=?]", admin_test_mail_path, count: 0
  end

  test "going out: the relay, the budgets, what waits and what couldn't go out, whose and why" do
    Emails::Enqueue.call(profiles(:bob), :test_mail)
    OutgoingEmail.create!(profile: profiles(:carol), kind: :test_mail, status: :sent, not_before: 10.minutes.ago, expires_at: 5.minutes.from_now,
                          claimed_at: 10.minutes.ago, message_id: "one@household.example")
    OutgoingEmail.create!(profile: profiles(:outsider), kind: :test_mail, status: :failed, not_before: 2.days.ago, expires_at: 2.days.ago + 15.minutes,
                          reason: :refused, detail: "550 5.1.1 <[address]>: Recipient address rejected")

    with_relay { get admin_emails_path }

    assert_response :success
    assert_select ".report-status--good .status-badge", text: /Going out/
    assert_select ".emails__value", text: "relay.example, port 587, STARTTLS"
    assert_select ".emails__facts", text: /household@household\.example/
    assert_select ".emails__facts", text: /1 of 6 used/
    assert_select "details[open]", text: /Waiting\s*1/ do
      assert_select ".emails__row", text: /Test mail\s*bob, Example/
    end
    assert_select "details[open]", text: /Couldn't go out in the last 30 days\s*1/ do
      assert_select ".emails__row", text: /dave, Elsewhere/
      assert_select ".emails__reason", text: "The relay refused it."
      assert_select ".emails__detail", text: "550 5.1.1 <[address]>: Recipient address rejected"
    end
    assert_select "a[href=?][data-turbo-method=post]", admin_test_mail_path
  end

  test "paused: until when, what to fix, and what the relay said" do
    with_relay do
      Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:login, reply: "535 5.7.8 Authentication credentials invalid"))
      get admin_emails_path
    end

    assert_select ".report-status--warning .status-badge", text: /Paused/
    assert_select ".report-status__now", text: /waits until \d\d:\d\d.*check the username and the password/
    assert_select ".report-mono", text: /535 5\.7\.8 Authentication credentials invalid/
    assert_select "details:not([open])", text: /Waiting\s*0/
    assert_select "a[href=?][data-turbo-method=post]", admin_test_mail_path
  end

  test "the test mail goes to the admin through the outbox at once, and ends a pause" do
    with_relay do
      Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:login))
      assert_enqueued_with(job: Emails::DrainJob) { post admin_test_mail_path, headers: { "HTTP_REFERER" => admin_emails_url } }
    end

    assert_redirected_to admin_emails_path
    assert_equal "A test mail is on its way to alice@example.com. How it went shows on this page.", flash[:notice]
    assert_equal [ @admin ], OutgoingEmail.test_mail.queued.map(&:profile)
    assert_nil Emails::RelayPause.current
  end

  test "no test while mail can't go, and no more than three a quarter of an hour" do
    post admin_test_mail_path, headers: { "HTTP_REFERER" => admin_emails_url }
    assert_redirected_to admin_emails_path
    assert_equal "Mail is off, or its relay isn't set. See the settings.", flash[:alert]
    assert_not OutgoingEmail.exists?

    counting_rate_limits do
      with_relay { 4.times { post admin_test_mail_path, headers: { "HTTP_REFERER" => admin_emails_url } } }
    end
    assert_equal I18n.t("rate_limit.exceeded"), flash[:alert]
    assert_equal 3, OutgoingEmail.count
  end
end
