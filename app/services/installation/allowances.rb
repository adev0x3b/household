# frozen_string_literal: true

module Installation
  # What this copy lets its people do (Platform's limits), as one form: a step
  # of the first setup and a card on /admin/settings.
  #
  #   allowances = Installation::Allowances.current.assign(params)
  #   allowances.valid?
  #   allowances.apply_to(setting)   # the Platform::Setting row, left unsaved
  class Allowances
    include ActiveModel::Model
    include ActiveModel::Attributes

    SWITCHES = %i[assistant uploads pictures invitations push_notifications release_check].freeze
    # Whole numbers, each nil for no limit.
    COUNTS = %i[assistant_messages_per_day household_size invitations_per_member].freeze

    attribute :assistant, :boolean
    attribute :uploads, :boolean
    attribute :pictures, :boolean
    attribute :invitations, :boolean
    attribute :push_notifications, :boolean
    attribute :release_check, :boolean
    attribute :assistant_messages_per_day, :integer
    attribute :household_size, :integer
    attribute :invitations_per_member, :integer
    # The quota as a whole number of one of these units: gigabytes where it
    # is a whole number of them, else megabytes (staging's 512 MB).
    QUOTA_UNITS = %w[MB GB].freeze

    attribute :files_quota_amount, :integer
    attribute :files_quota_unit, :string

    validates :assistant_messages_per_day, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    # None at all is what the invitations switch and an empty field say.
    validates :household_size, :invitations_per_member, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :files_quota_amount, numericality: { only_integer: true, greater_than: 0 }
    validates :files_quota_unit, inclusion: { in: QUOTA_UNITS }

    def self.param_key = :allowances

    def self.fields = attribute_names.map(&:to_sym)

    # What is in use now: what was saved, else where a new row starts.
    def self.current
      amount, unit = quota_in_units(Platform.files_quota)
      new(assistant: Platform.assistant?, uploads: Platform.uploads?, pictures: Platform.pictures?,
          invitations: Platform.invitations?, push_notifications: Platform.push_notifications?,
          release_check: Platform.release_check?, assistant_messages_per_day: Platform.assistant_messages_per_day,
          household_size: Platform.household_size, invitations_per_member: Platform.invitations_per_member,
          files_quota_amount: amount, files_quota_unit: unit)
    end

    # The first setup starts from the same values: the environment's and the defaults.
    def self.for_setup = current

    # bytes as [ amount, unit ], rounded up to a whole megabyte.
    def self.quota_in_units(bytes)
      return [ bytes / 1.gigabyte, "GB" ] if (bytes % 1.gigabyte).zero?

      [ (bytes / 1.megabyte.to_f).ceil, "MB" ]
    end

    def assign(values)
      given = values.to_h.symbolize_keys
      SWITCHES.each { |name| public_send(:"#{name}=", given[name]) if given.key?(name) }
      COUNTS.each { |name| public_send(:"#{name}=", given[name].presence) if given.key?(name) }
      %i[files_quota_amount files_quota_unit].each { |name| public_send(:"#{name}=", given[name]) if given.key?(name) }
      self
    end

    # Writes every limit on the row; the caller saves.
    def apply_to(setting)
      SWITCHES.each { |name| setting[name] = public_send(name) }
      COUNTS.each { |name| setting[name] = public_send(name) }
      setting.files_quota = files_quota_amount * Platform::Size::UNITS.fetch(files_quota_unit)
      setting
    end

    # Always a step of the first setup.
    def asked?(_form) = true
  end
end
