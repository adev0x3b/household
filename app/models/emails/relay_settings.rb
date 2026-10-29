# frozen_string_literal: true

module Emails
  # The SMTP relay mail goes out through: each field as the admin saved it
  # (Installation::Mail), else the environment's (Platform.value). The
  # environment's login goes only to the environment's relay: a relay
  # saved on the page gets the login saved with it, or none.
  #
  #   relay = Emails::RelaySettings.current
  #   relay.configured?   # a host and a sender, and a port and a TLS mode that are ones
  #   relay.problem       # what stops it otherwise: :host, :from, :port, :tls or :login_in_clear
  #   relay.smtp          # the mail gem's SMTP settings (Emails::Relay)
  #   Emails::RelaySettings.source(:smtp_username)   # => :saved, :env or nil, for the settings page
  class RelaySettings
    # starttls: the relay must offer STARTTLS; tls: TLS from the first
    # byte; none: plain, for a catcher on the same machine, which takes no
    # login. A relay that doesn't offer what is asked is refused, never
    # spoken to in the clear.
    ENCRYPTION = {
      "starttls" => { enable_starttls: :always },
      "tls" => { tls: true },
      "none" => { enable_starttls: false, enable_starttls_auto: false }
    }.freeze
    TLS_MODES = ENCRYPTION.keys.freeze
    # The port each way of speaking is offered on, unless the admin says.
    DEFAULT_PORTS = { "starttls" => 587, "tls" => 465, "none" => 25 }.freeze

    LOGIN = %i[smtp_username smtp_password].freeze

    attr_reader :host, :port, :username, :password, :tls, :from

    def self.current
      new(host: Platform.value(:smtp_host), port: Platform.value(:smtp_port), username: field(:smtp_username),
          password: field(:smtp_password), tls: Platform.value(:smtp_tls), from: Platform.value(:mail_from))
    end

    # Where a field of the relay in use comes from: :saved, :env, or nil
    # when neither gives it one.
    def self.source(key)
      if Platform.saved_value(key) then :saved
      elsif field(key) then :env
      end
    end

    # A field's value in use: the saved one, else the environment's, which
    # for the login is only the environment's relay's.
    def self.field(key)
      if LOGIN.include?(key) && !environment_relay?
        Platform.saved_value(key)
      else
        Platform.value(key)
      end
    end

    # Whether the relay in use is the one the environment names, however it
    # is written.
    def self.environment_relay? = Platform.value(:smtp_host).to_s.strip.casecmp?(Platform.env_value(:smtp_host).to_s.strip)
    private_class_method :environment_relay?

    def initialize(host:, port:, username:, password:, tls:, from:)
      @host = host.to_s.strip.presence
      @tls = tls.to_s.strip.downcase.presence || TLS_MODES.first
      @port = port.to_s.strip.empty? ? DEFAULT_PORTS[@tls] : port.to_s.strip[/\A\d+\z/]&.to_i
      @username = username.to_s.strip.presence
      @password = password.presence
      @from = from.to_s.strip.presence
    end

    def configured? = problem.nil?

    # What keeps mail from going out, for the admin's pages; nil when
    # nothing does. A login without one of its halves isn't one here: the
    # relay says so when it refuses (Emails::Relay), and a sender is only
    # checked for its form, since only the relay knows which it allows.
    def problem
      if host.nil? then :host
      elsif from.nil? || !from.match?(URI::MailTo::EMAIL_REGEXP) then :from
      elsif !TLS_MODES.include?(tls) then :tls
      elsif port.nil? || !port.between?(1, 65_535) then :port
      elsif tls == "none" && (username || password) then :login_in_clear
      end
    end

    def smtp
      { address: host, port: port, domain: from.split("@").last, user_name: username, password: password,
        authentication: (:plain if username) }.merge(ENCRYPTION.fetch(tls))
    end
  end
end
