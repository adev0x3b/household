# frozen_string_literal: true

require "test_helper"
require "mail"

# What the relay answers, as the drain hears it: not answering, this copy's
# own settings refused, or one message refused. Each error's message stays
# the same from one time to the next; what the relay said is kept apart.
class Emails::RelayTest < ActiveSupport::TestCase
  def mail = Mail.new(from: "household@household.example", to: "alice@example.com", subject: "Hello", body: "Hello")

  def settings(**changes)
    Emails::RelaySettings.new(host: "relay.example", port: 587, username: "household", password: "relay-password", tls: "starttls",
                              from: "household@household.example", **changes)
  end

  def reply(text) = Net::SMTP::Response.parse(text)

  # The relay's answer, raised where the mail gem raises it.
  def answered(error)
    message = mail
    swapping(message, :deliver!, -> { raise error }) { Emails::Relay.deliver(message, settings: settings) }
  end

  test "hands the mail to the relay the settings name" do
    message = mail
    used = nil
    swapping(message, :deliver!, -> { used = delivery_method }) { Emails::Relay.deliver(message, settings: settings) }

    assert_kind_of Mail::SMTP, used
    assert_equal [ "relay.example", 587, "household", :always ], used.settings.values_at(:address, :port, :user_name, :enable_starttls)
    assert_equal [ Emails::Relay::TIMEOUT ] * 2, used.settings.values_at(:open_timeout, :read_timeout)
  end

  test "a relay that doesn't answer, or asks to try later, is Unavailable" do
    [ Errno::ECONNREFUSED.new, Net::OpenTimeout.new, EOFError.new, IOError.new, OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof") ].each do |error|
      assert_raises(Emails::Relay::Unavailable, match: /\AThe mail relay isn't answering \(\w+\)\z/) { answered(error) }
    end

    busy = assert_raises(Emails::Relay::Unavailable) { answered(Net::SMTPServerBusy.new(reply("451 4.3.0 Too many messages, try later"))) }
    assert_equal "The mail relay asked to try later (451 4.3.0)", busy.message
    assert_equal "451 4.3.0 Too many messages, try later", busy.reply
  end

  test "a login it can't check now is Unavailable, not a wrong login" do
    later = assert_raises(Emails::Relay::Unavailable) do
      answered(Net::SMTPAuthenticationError.new(reply("454 4.7.0 Temporary authentication failure")))
    end

    assert_equal "The mail relay asked to try later (454 4.7.0)", later.message
  end

  test "this copy's own settings refused is Misconfigured, saying what to fix and where" do
    {
      Net::SMTPAuthenticationError.new(reply("535 5.7.8 Authentication credentials invalid")) => :login,
      Net::SMTPUnsupportedCommand.new(nil, message: "STARTTLS is not supported on this server") => :starttls,
      Net::SMTPFatalError.new(reply("553 5.7.1 <household@household.example>: Sender address rejected: not owned by user")) => :sender,
      Net::SMTPSyntaxError.new(reply("501 5.1.8 Bad sender's system address")) => :sender,
      Net::SMTPFatalError.new(reply("553 Sender not allowed")) => :sender,
      Net::SMTPSyntaxError.new(reply("503 Bad sequence of commands")) => :sender,
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: certificate verify failed (hostname mismatch)") => :certificate,
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: wrong version number") => :encryption,
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: record layer failure") => :encryption
    }.each do |error, problem|
      refused = assert_raises(Emails::Relay::Misconfigured) { answered(error) }

      assert_equal problem, refused.problem, error.message
      assert_equal Emails::Relay::MISCONFIGURED.fetch(problem), refused.message
      assert_includes refused.message, "/admin/settings"
      assert_equal problem == :sender, refused.maybe_the_message?, "only a refusal in a reply's words may be of the message"
    end
  end

  test "half a login never reaches the relay" do
    message = mail
    swapping(message, :deliver!, -> { flunk "handed to the relay" }) do
      { { password: nil } => :password, { username: nil } => :username }.each do |changes, problem|
        refused = assert_raises(Emails::Relay::Misconfigured) { Emails::Relay.deliver(message, settings: settings(**changes)) }

        assert_equal problem, refused.problem
      end
    end
  end

  test "one message or address refused is Refused, its message naming the code alone" do
    refused = assert_raises(Emails::Relay::Refused) do
      answered(Net::SMTPFatalError.new(reply("550 5.1.1 <alice@example.com>: Recipient address rejected")))
    end

    assert_equal "The mail relay refused a message (550 5.1.1)", refused.message
    assert_includes refused.reply, "alice@example.com"
    assert_raises(Emails::Relay::Refused, match: "(552)") { answered(Net::SMTPFatalError.new(reply("552 Message size exceeds fixed limit"))) }
  end
end
