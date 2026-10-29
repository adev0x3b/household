# frozen_string_literal: true

require "test_helper"

# Mail about an account: each to the address it is for, worded in the
# person's language, leading to their account page or to the link's page.
class AccountMailerTest < ActionMailer::TestCase
  setup { @alice = profiles(:alice) }

  test "the link that confirms an address goes to that address, with its page's link and how long it works" do
    mail = account_mail(:email_confirmation, to: "alice@new.example", token: "the-token")

    assert_equal [ "alice@new.example" ], mail.to
    assert_equal "Confirm your address for Household", mail.subject
    text = mail.text_part.body.to_s
    assert_includes text, "confirm alice@new.example as the address"
    assert_includes text, "24 hours"
    assert_includes text, "http://example.com/account/email_confirmation?token=the-token"
    assert_select_in(mail.html_part.body.to_s, "a[href='http://example.com/account/email_confirmation?token=the-token']", count: 2)
  end

  test "the link to set a forgotten password goes to the address in use, naming the account and how long the link works" do
    mail = account_mail(:password_link, token: "the-token")

    assert_equal [ "alice@example.com" ], mail.to
    assert_equal "Set a new password for Household", mail.subject
    text = mail.text_part.body.to_s
    assert_includes text, "your Household account, #{@alice.username}"
    assert_includes text, "30 minutes"
    assert_includes text, "Set a new password:\nhttp://example.com/profiles/password/edit?reset_password_token=the-token"
  end

  test "a new address asked for, and taken over, is told to the address confirmed before, with when on the person's clock" do
    @alice.update!(time_zone: "Europe/Rome")
    at = Time.utc(2026, 10, 29, 9, 30)
    requested = account_mail(:email_change_requested, to: "alice@old.example", at: at)
    changed = account_mail(:email_changed, to: "alice@old.example", at: at)

    assert_equal [ [ "alice@old.example" ] ] * 2, [ requested.to, changed.to ]
    assert_includes requested.text_part.body.to_s, "Asked on October 29, 2026 10:30."
    assert_includes changed.text_part.body.to_s, "is now alice@example.com"
    assert_includes changed.text_part.body.to_s, "Open your account:\nhttp://example.com/account"
  end

  test "a changed password is told to the address it was queued for, in the person's language" do
    @alice.update!(locale: "it")
    mail = account_mail(:password_changed, to: "alice@old.example", at: Time.zone.local(2026, 10, 29, 9, 30))

    assert_equal [ "alice@old.example" ], mail.to
    assert_equal "La tua password di Household è cambiata", mail.subject
    assert_includes mail.text_part.body.to_s, "Cambiata il 29 ottobre 2026, 09:30."
  end

  test "a mail goes to one mailbox: an address that lists several, or names someone, is refused before anything goes" do
    [ "alice@example.com,bob", "alice@example.com bob@example.com", "Alice <alice@example.com>" ].each do |to|
      assert_raises(ArgumentError, to) { account_mail(:password_changed, to: to, at: Time.current) }
    end
  end

  test "a mail goes only to the address it was made for: one Mail would decode into another is refused" do
    to = "=?utf-8?q?carol=40gmail.com=3e_notify=3dnever?=@example.com"
    assert_match URI::MailTo::EMAIL_REGEXP, to, "a mailbox, to the pattern an address is typed against"

    assert_raises(ArgumentError) { account_mail(:password_changed, to: to, at: Time.current) }
  end

  private

  def account_mail(action, **params)
    with_relay { @alice.as_viewer { AccountMailer.with(profile: @alice, **params).public_send(action).message } }
  end

  def assert_select_in(html, ...) = assert_select(Nokogiri::HTML5(html), ...)
end
