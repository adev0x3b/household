# frozen_string_literal: true

module Setup
  # The first setup's answers, one form over every step (Setup::STEPS),
  # kept in ActiveModel's contract: valid? checks each step that is asked,
  # and each keeps its own errors. Saved by Setup::Complete.
  #
  #   form = Setup::Form.new(params[:setup])
  #   form.valid?
  #   form.step(Setup::Account).username
  class Form
    # What the page may send, step by step, for params.expect.
    def self.fields = STEPS.map { |step| { step.param_key => step.fields } }

    def initialize(values = {})
      given = values.to_h.with_indifferent_access
      @steps = STEPS.index_with { |step| step.for_setup.assign(given.fetch(step.param_key, {})) }
      step(Setup::Housemates).owner_email = step(Setup::Account).email
      step(Setup::Housemates).allowances = step(Installation::Allowances)
    end

    def step(kind) = @steps.fetch(kind)

    def steps = @steps.values

    def asked = steps.select { |step| step.asked?(self) }

    # Every step asked is checked, not only up to the first wrong one, so each shows its errors.
    def valid? = asked.map(&:valid?).all?

    # The first step with something to fix, where the page opens again.
    def first_invalid = asked.find { |step| step.errors.any? }
  end
end
