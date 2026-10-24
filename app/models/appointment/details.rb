# frozen_string_literal: true

class Appointment
  class Details < ::Details::Base
    self.table_name = "appointment_details"

    enum :kind, { medical: 0, work: 1, social: 2, personal: 3, other: 4 }

    inherits :kind, :counterpart

    # Who a past visit was with, and what kind it was, stay as they were.
    def self.recorded = %i[kind counterpart]
    series_requires :kind

    after_initialize { self.kind ||= Kind::DEFAULT if series? && new_record? }

    def kind_object = Kind.new(kind.presence || Kind::DEFAULT)
  end
end
