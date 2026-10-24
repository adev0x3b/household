# frozen_string_literal: true

# The first setup in the browser, on a fresh copy: who sets it up, their
# household and everything the installation allows (Setup::Form), saved at
# once by Setup::Complete.
module Setup
  # Everything the first setup asks, in the order it asks it. Adding a step
  # is a form object here and its view in Views::Setup::Steps::BY_STEP.
  # Each step answers fields (what the page may send), for_setup (what it
  # starts from), assign, asked? (whether the answers before it call for
  # it) and ActiveModel's errors.
  STEPS = [
    Setup::Account,
    Setup::HouseholdDetails,
    Installation::Allowances,
    Installation::Assistant,
    Installation::Books,
    Setup::Housemates
  ].freeze
end
