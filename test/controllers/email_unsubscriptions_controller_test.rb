# frozen_string_literal: true

require "test_helper"

# The link at the foot of a reminder mail: a page that changes nothing
# until its button is pressed, or a mail client presses it in one click,
# for whoever holds the link and nobody else.
class EmailUnsubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @alice.update!(email_confirmed_at: 1.day.ago)
    @token = @alice.generate_token_for(:email_unsubscription)
    @reminder = events(:groceries).event_reminders.create!(profile: @alice, offset_minutes: 60, by_email: true)
  end

  test "the link opens a page that asks before it stops anything, and tells no other site where it came from" do
    get email_unsubscription_path(token: @token)

    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_select "h1", text: "Reminders by email"
    assert_select "form[action=?] input[name=token][value=?]", email_unsubscription_path, @token
    assert_predicate @reminder.reload, :by_email?
  end

  test "its button stops every reminder by email, tells the bell, and comes back to the page saying so" do
    post email_unsubscription_path, params: { token: @token }

    assert_redirected_to email_unsubscription_path(token: @token)
    assert_not @reminder.reload.by_email?
    assert_equal [ "reminder_mails_stopped" ], @alice.notifications.pluck(:kind)
    follow_redirect!
    assert_toast "Your reminders no longer come by email."
    assert_select ".auth-card__subtitle", text: /None of your reminders comes by email/
    assert_select "form[action=?]", email_unsubscription_path, count: 0
  end

  test "a mail client presses it in one click, with no form token, and is answered without a redirect" do
    with_forgery_protection { post email_unsubscription_path(token: @token), params: { "List-Unsubscribe" => "One-Click" } }

    assert_response :ok
    assert_not @reminder.reload.by_email?
    assert_equal [ "reminder_mails_stopped" ], @alice.notifications.pluck(:kind)
  end

  test "a mail client's one click on a link that no longer works stops nothing, and hears so without a redirect" do
    travel 1.second
    @alice.update!(email_confirmed_at: Time.current)

    with_forgery_protection { post email_unsubscription_path(token: @token), params: { "List-Unsubscribe" => "One-Click" } }

    assert_response :unprocessable_content
    assert_predicate @reminder.reload, :by_email?
  end

  test "a link for an address confirmed again since, too old, or made up stops nothing, and says it no longer works" do
    travel 1.second
    @alice.update!(email_confirmed_at: Time.current)
    stale = @token
    old = @alice.generate_token_for(:email_unsubscription)
    travel Profile::EMAIL_UNSUBSCRIPTION_FOR + 1.second

    [ stale, old, "made-up" ].each do |token|
      get email_unsubscription_path(token: token)
      assert_select ".auth-card__subtitle", text: /This link no longer works/
      assert_select "form[action=?]", email_unsubscription_path, count: 0

      post email_unsubscription_path, params: { token: token }, as: :turbo_stream
      assert_response :unprocessable_content
      assert_toast(/This link no longer works/)
    end
    assert_predicate @reminder.reload, :by_email?
  end

  test "whoever opens a link again and again from one address is slowed" do
    counting_rate_limits do
      20.times { get email_unsubscription_path(token: "made-up") }
      get email_unsubscription_path(token: @token)
    end

    assert_redirected_to root_path
    assert_equal I18n.t("rate_limit.exceeded"), flash[:alert]
  end

  private

  # The test environment turns CSRF protection off; a mail client's press
  # is about where it stays off in production.
  def with_forgery_protection
    protecting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = protecting
  end
end
