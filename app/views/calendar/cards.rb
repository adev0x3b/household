# frozen_string_literal: true

# One card per kind of series, listed here on the view side so that a kind
# never names its card, nor its icon: a model knows no view. The test over
# Event.types fails until a new kind has its line.
module Views::Calendar::Cards
  BY_KIND = {
    Task => Views::Calendar::Cards::TaskCard,
    Appointment => Views::Calendar::Cards::AppointmentCard,
    Medication => Views::Calendar::Cards::MedicationCard,
    Meal => Views::Calendar::Cards::MealCard,
    LabTestResult => Views::Calendar::Cards::LabTestResultCard,
    Transaction => Views::Calendar::Cards::TransactionCard
  }.freeze

  def self.for(kind) = BY_KIND.fetch(kind)

  # The icon of a series, wherever it is listed.
  def self.icon_of(event) = self.for(event.class).icon_of(event)
end
