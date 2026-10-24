# frozen_string_literal: true

class Appointment
  # What kind of appointment a series is — a visit to a doctor, an
  # interview, meeting friends — and everything that follows from it: the
  # section it belongs to, how the person it's with is called, and what
  # its fee is filed under. Kinds differ in data, not behaviour,
  # so a kind is a value; the day one needs behaviour of its own it becomes
  # an Appointment subclass.
  class Kind
    ALL = %w[medical work social personal other].freeze
    DEFAULT = "medical"
    SECTIONS = { "medical" => :healthcare }.freeze
    FEE_CATEGORIES = { "medical" => :healthcare, "social" => :entertainment }.freeze

    attr_reader :name

    def initialize(name)
      name = name.to_s
      raise ArgumentError, "unknown appointment kind #{name.inspect}" unless ALL.include?(name)

      @name = name
    end

    def self.all = ALL.map { |name| new(name) }
    def self.default = new(DEFAULT)
    # The kinds whose appointments belong to `section`.
    def self.for_section(section) = ALL.select { |name| new(name).section == section.to_sym }

    def section = SECTIONS.fetch(name, :agenda)
    def fee_category = FEE_CATEGORIES.fetch(name, :miscellaneous)
    # The form's and card's word for who it is with: "Provider" for a
    # visit, "With" for the rest.
    def counterpart_label_key = "appointments.form.counterpart.#{name}"
    # What a form suggests for its `field` (:title, :location) in this kind.
    def placeholder_key(field) = "appointments.form.placeholders.#{name}.#{field}"
    def label = I18n.t("appointments.kind.#{name}")
    def to_s = name
    def medical? = name == "medical"
    def ==(other) = other.is_a?(Kind) && other.name == name
    alias eql? ==
    def hash = name.hash
  end
end
