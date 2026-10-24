# frozen_string_literal: true

# A meeting at a time and a place: a visit to a doctor (Healthcare), an
# interview, a dinner with friends (Agenda). Its kind (Appointment::Kind)
# decides the section, the word for who it's with and what its fee is
# filed under.
class Appointment < Event
  has_details "Appointment::Details"

  validates :title, presence: true

  def self.starting_section = Kind.default.section

  # Appointments belong to a section by kind: the series whose kind says so.
  def self.section_scope(section)
    kinds = Kind.for_section(section)
    return none if kinds.empty?

    joins(:details).where(appointment_details: { kind: kinds.map { |name| Details.kinds.fetch(name) } })
  end

  def kind = Kind.new(details.kind.presence || Kind::DEFAULT)
  def section = kind.section
  def fee_category = kind.fee_category
  def counterpart = details.counterpart

  # Due at its start time, or in the morning when it has none.
  def due_clock(occurrence)
    return [ [ occurrence.start_time.hour, occurrence.start_time.min ], true ] if occurrence.start_time

    [ Events::TimesOfDay::MORNING, false ]
  end

  def cost_counterpart(occurrence) = occurrence.details.counterpart

  # Title of the fee attached to one of its days.
  def cost_title(occurrence)
    date = I18n.l(occurrence.date, format: :long)
    counterpart = occurrence.details.counterpart
    return I18n.t("appointments.form.transaction_title", date: date) if counterpart.blank?

    I18n.t("appointments.form.transaction_title_with_counterpart", counterpart: counterpart, date: date)
  end
end
