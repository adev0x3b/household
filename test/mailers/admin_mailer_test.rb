# frozen_string_literal: true

require "test_helper"

# The admin's test mail, and with it what every mail is: to one address,
# from the relay's sender under the app's name, in text and in HTML, with
# nothing to load and nothing a person typed read as markup.
class AdminMailerTest < ActionMailer::TestCase
  test "to the admin alone, from the app, with the page it was sent from" do
    mail = admin_test_mail(profiles(:alice))

    assert_equal [ "alice@example.com" ], mail.to
    assert_nil mail.cc
    assert_nil mail.bcc
    assert_equal "Household <household@household.example>", mail[:from].value
    assert_equal "A test mail from Household", mail.subject
    assert_equal %w[text/plain text/html], mail.parts.map(&:mime_type)

    text = mail.text_part.body.to_s
    assert text.start_with?("Hello Alice,")
    assert_includes text, "Open the mail page:\nhttp://example.com/admin/emails"

    html = mail.html_part.body.to_s
    assert_match(/\A<!doctype html>/i, html)
    assert_select_in(html, "html[lang=en] h1", text: "Hello Alice,")
    assert_select_in(html, "a[href='http://example.com/admin/emails']", count: 2)
    assert_no_match(/<img|<script|<link|src=|url\(/i, html, "nothing to load, so nothing tells anyone the mail was opened")
  end

  test "a name a person typed is text in both parts, and never in a header" do
    profiles(:alice).update!(first_name: "<b>Alice</b> & \"co\" <eve@example.com>")
    mail = admin_test_mail(profiles(:alice))

    assert_includes mail.text_part.body.to_s, "Hello <b>Alice</b> & \"co\" <eve@example.com>,"
    assert_select_in(mail.html_part.body.to_s, "h1", text: "Hello <b>Alice</b> & \"co\" <eve@example.com>,")
    assert_select_in(mail.html_part.body.to_s, "h1 b", count: 0)
    assert_equal [ "alice@example.com" ], mail.to
    assert_no_match(/Alice|eve/, mail.header.fields.map(&:to_s).join("\n"))
  end

  test "in the admin's language" do
    profiles(:alice).update!(locale: "it")
    mail = admin_test_mail(profiles(:alice))

    assert_equal "Un'email di prova da Household", mail.subject
    assert_select_in(mail.html_part.body.to_s, "html[lang=it] h1", text: "Ciao Alice,")
  end

  private

  def admin_test_mail(profile) = with_relay { profile.as_viewer { AdminMailer.with(profile: profile).test_mail.message } }

  def assert_select_in(html, ...) = assert_select(Nokogiri::HTML5(html), ...)
end
