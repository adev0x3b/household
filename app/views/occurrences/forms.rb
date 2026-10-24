# frozen_string_literal: true

# One form per kind of record the assistant drafts or a day's address
# opens, listed here on the view side so that a kind never names its form:
# a model knows no view. A series' form is a Views::Occurrences::Form, so
# whoever opens one needs to know nothing of the kind; a purchase's takes
# its own arguments. The test over Event.types fails until a new kind has its line.
module Views::Occurrences::Forms
  BY_KIND = {
    Task => Views::Tasks::Modals::Form,
    Appointment => Views::Appointments::Modals::Form,
    Medication => Views::Medications::Modals::Form,
    Meal => Views::Meals::Modals::Form,
    LabTestResult => Views::LabTestResults::Modals::Form,
    Transaction => Views::Transactions::Modals::Form,
    SupplyPurchase => Views::SupplyPurchases::Modals::Form,
    IngredientPurchase => Views::IngredientPurchases::Modals::Form
  }.freeze

  def self.for(kind) = BY_KIND.fetch(kind)
end
