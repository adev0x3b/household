# frozen_string_literal: true

require "net/smtp"

module Emails
  # The SMTP relay the installation's mail goes out through, set by the
  # admin (Emails::RelaySettings). What it answers is one of three things,
  # each its own error, which the drain answers differently (Emails::Drain):
  #
  #   Unavailable    it isn't answering, or asks to try later: the mail waits
  #   Misconfigured  it refuses this copy's own settings (the login, the
  #                  sender, the encryption): every mail would be refused
  #                  alike until the admin fixes them, which the message says.
  #                  A sender refused may be a recipient or a message refused
  #                  in the same words (maybe_the_message?)
  #   Refused        it refuses this one message or address, for good
  #
  # An error's message stays the same from one time to the next, so the
  # admin hears of each kind once; the relay's own reply, which may quote
  # an address, is only the error's `reply`, kept with its addresses masked.
  #
  #   Emails::Relay.deliver(mail)   # a Mail::Message, sent
  class Relay < ApplicationClient
    # A slow relay holds the drain, never a person's request: this long to
    # connect, and to wait for each of its answers.
    TIMEOUT = 15 # seconds
    WHERE_TO_FIX = "the Mail settings on /admin/settings"
    # What the admin has to fix when the relay refuses this copy, each with
    # the message reported, which says where.
    MISCONFIGURED = {
      login: "The mail relay refused the login: check the username and the password in #{WHERE_TO_FIX}",
      password: "The mail relay has a username but no password: set it in #{WHERE_TO_FIX}",
      username: "The mail relay has a password but no username: set it in #{WHERE_TO_FIX}",
      starttls: "The mail relay doesn't offer STARTTLS: check the port and the encryption in #{WHERE_TO_FIX}",
      encryption: "The mail relay doesn't speak TLS from the start on its port: check the port and the encryption in #{WHERE_TO_FIX}",
      certificate: "The mail relay's certificate doesn't verify for its name: check the relay server in #{WHERE_TO_FIX}",
      sender: "The mail relay refused to send for this copy: check that its login may send as the sender address in #{WHERE_TO_FIX}"
    }.freeze

    class Error < ApplicationClient::Error
      attr_reader :reply

      def initialize(message, reply: nil)
        super(message)
        @reply = reply
      end

      # What the outbox keeps of it beside its reason (OutgoingEmail): the
      # relay's reply with its addresses masked, else what failed under it.
      def detail = reply.present? ? Emails.without_addresses(reply.squish).truncate(255) : cause&.class&.name
    end

    class Unavailable < Error; end

    class Refused < Error
      # Named by the reply's code, so the admin hears of each kind of refusal once.
      def self.of(reply, code:) = new("#{Relay.service} refused a message (#{code})", reply: reply)
    end

    class Misconfigured < Error
      # One of MISCONFIGURED's keys, which the admin's pages word.
      attr_reader :problem

      def initialize(problem, reply: nil)
        super(MISCONFIGURED.fetch(problem), reply: reply)
        @problem = problem
      end

      # Whether the reply may as well be about the one message: a relay
      # refuses a sender it won't send for, a recipient it won't take and a
      # message its filter stops with the same codes.
      def maybe_the_message? = problem == :sender

      # The same reply as the refusal of one message: what the drain reports
      # until the mail around it shows the settings are wrong
      # (Emails::Drain#maybe_misconfigured).
      def as_refusal = Refused.of(reply, code: reply.to_s[REPLY_CODE])
    end

    # Replies about this copy rather than one message: authentication and
    # policy (5.7), a sender's address or domain it won't take (5.1.7,
    # 5.1.8), a command out of order or not understood (5.5, 503). A relay
    # without enhanced codes refuses a sender with 553.
    SETTINGS_CODES = /\A(5\.7\.|5\.5\.|5\.1\.7\z|5\.1\.8\z)/
    SETTINGS_REPLIES = %w[503 553].freeze
    # A reply's code, and its enhanced code when it has one: "550 5.1.1".
    REPLY_CODE = /\A\d{3}(?:[ -]\d\.\d{1,3}\.\d{1,3})?/
    # What OpenSSL says when the other end answers TLS with something else:
    # a relay that starts in the clear, asked for TLS from the start.
    NOT_TLS = /wrong version number|packet length too long|record layer failure|unknown protocol/

    def self.service = "The mail relay"

    def self.deliver(mail, settings: RelaySettings.current)
      raise Misconfigured, :password if settings.username && settings.password.nil?
      raise Misconfigured, :username if settings.password && settings.username.nil?

      mail.delivery_method(:smtp, settings.smtp.merge(open_timeout: TIMEOUT, read_timeout: TIMEOUT))
      perform(mail)
    end

    # The one call that reaches the network; tests stub it.
    def self.perform(mail)
      mail.deliver!
    rescue Net::SMTPAuthenticationError => e
      raise Unavailable.new("#{service} asked to try later (#{code(e)})", reply: e.message) if e.message.start_with?("4")

      raise Misconfigured.new(:login, reply: e.message)
    rescue Net::SMTPUnsupportedCommand => e
      raise Misconfigured.new(:starttls, reply: e.message)
    rescue Net::SMTPServerBusy => e
      raise Unavailable.new("#{service} asked to try later (#{code(e)})", reply: e.message)
    rescue Net::SMTPSyntaxError, Net::SMTPFatalError, Net::SMTPUnknownError => e
      raise Misconfigured.new(:sender, reply: e.message) if about_settings?(e)

      raise Refused.of(e.message, code: code(e))
    rescue OpenSSL::SSL::SSLError => e
      raise Misconfigured.new(:certificate, reply: e.message) if e.message.include?("certificate verify failed")
      raise Misconfigured.new(:encryption, reply: e.message) if e.message.match?(NOT_TLS)

      raise Unavailable, "#{service} isn't answering (#{e.class.name.demodulize})"
    rescue *UNREACHABLE, IOError => e
      raise Unavailable, "#{service} isn't answering (#{e.class.name.demodulize})"
    end

    def self.code(error) = error.message[REPLY_CODE] || error.class.name.demodulize

    def self.about_settings?(error)
      enhanced = error.message[/\A\d{3}[ -](\d\.\d{1,3}\.\d{1,3})/, 1]
      enhanced ? enhanced.match?(SETTINGS_CODES) : SETTINGS_REPLIES.include?(error.message[0, 3])
    end
    private_class_method :code, :about_settings?
  end
end
