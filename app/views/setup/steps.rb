# frozen_string_literal: true

# Each step of the first setup (Setup::STEPS) and the view that draws it,
# listed here so no form object names a view. Every view takes the step's
# fields builder and the step.
module Views::Setup::Steps
  BY_STEP = {
    Setup::Account => Views::Setup::Steps::Account,
    Setup::HouseholdDetails => Views::Setup::Steps::HouseholdDetails,
    Installation::Allowances => Views::Installation::Allowances,
    Installation::Assistant => Views::Setup::Steps::Assistant,
    Installation::Books => Views::Installation::Books,
    Setup::Housemates => Views::Setup::Steps::Housemates
  }.freeze
end
