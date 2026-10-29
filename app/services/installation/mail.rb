# frozen_string_literal: true

module Installation
  # What the installation mails and through which relay, as one form: a step
  # of the first setup and a card on /admin/settings. The relay's fields
  # left empty follow the environment (Emails::RelaySettings); its password
  # is a secret, never shown back, and a blank field keeps the saved one.
  #
  #   mail = Installation::Mail.current.assign(params)
  #   mail.valid?
  #   mail.apply_to(setting)   # the Platform::Setting row, left unsaved
  class Mail
    include ActiveModel::Model
    include ActiveModel::Attributes

    RELAY = %i[smtp_host smtp_port smtp_tls smtp_username mail_from].freeze
    # Whole numbers, each empty for its default: mail always has a budget.
    COUNTS = %i[mails_per_hour mails_per_day reminder_mails_per_day].freeze

    attribute :outgoing_mail, :boolean
    attribute :smtp_host, :string
    attribute :smtp_port, :string
    attribute :smtp_tls, :string
    attribute :smtp_username, :string
    attribute :smtp_password, :string
    attribute :mail_from, :string
    attribute :mails_per_hour, :integer
    attribute :mails_per_day, :integer
    attribute :reminder_mails_per_day, :integer

    # A name or an address, without a scheme, a path or a port.
    validates :smtp_host, format: { with: /\A[a-z0-9]([a-z0-9.-]*[a-z0-9])?\z/i }, allow_nil: true
    validates :smtp_port, numericality: { only_integer: true, in: 1..65_535 }, allow_nil: true
    validates :smtp_tls, inclusion: { in: Emails::RelaySettings::TLS_MODES }, allow_nil: true
    validates :mail_from, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
    validates :mails_per_hour, numericality: { only_integer: true, greater_than_or_equal_to: Platform.limit(:mails_per_hour).minimum }, allow_nil: true
    validates :mails_per_day, numericality: { only_integer: true, greater_than_or_equal_to: Platform.limit(:mails_per_day).minimum }, allow_nil: true
    validates :reminder_mails_per_day, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    # A login is never sent in the clear (Emails::RelaySettings).
    validate :login_with_encryption

    def self.param_key = :mail

    def self.fields = attribute_names.map(&:to_sym)

    # What is in use now: the switch and the budgets, and the relay's fields
    # as saved (an empty one follows the environment, which the view shows).
    def self.current
      saved = Platform.saved
      new(outgoing_mail: Platform.outgoing_mail?, mails_per_hour: Platform.mails_per_hour, mails_per_day: Platform.mails_per_day,
          reminder_mails_per_day: Platform.reminder_mails_per_day, **RELAY.index_with { saved&.public_send(_1) })
    end

    # The first setup starts from the same values: the environment's and the defaults.
    def self.for_setup = current

    def assign(values)
      given = values.to_h.symbolize_keys
      self.outgoing_mail = given[:outgoing_mail] if given.key?(:outgoing_mail)
      RELAY.each { |name| public_send(:"#{name}=", given[name].to_s.strip.presence) if given.key?(name) }
      COUNTS.each { |name| public_send(:"#{name}=", given[name].presence) if given.key?(name) }
      self.smtp_password = given[:smtp_password].to_s.strip.presence
      self
    end

    # Writes the switch, the budgets and the relay on the row; the caller saves.
    def apply_to(setting)
      setting.outgoing_mail = outgoing_mail
      COUNTS.each { |name| setting[name] = public_send(name) }
      RELAY.each { |name| setting[name] = public_send(name) }
      setting.smtp_password = smtp_password if smtp_password.present?
      setting
    end

    # Always a step of the first setup: a copy with no relay leaves it empty.
    def asked?(_form) = true

    private

    def login_with_encryption
      errors.add(:smtp_tls, :login_in_clear) if smtp_tls == "none" && (smtp_username || smtp_password)
    end
  end
end
