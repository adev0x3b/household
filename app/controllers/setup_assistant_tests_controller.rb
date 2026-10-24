# frozen_string_literal: true

# The first setup's Test press on the assistant step: whether the provider,
# key and model typed so far reach the model, and the models that key
# lists, before anything is saved. Open, like the setup itself, only to a
# browser that gave the setup code, and limited by address, since every
# press asks the provider.
class SetupAssistantTestsController < ApplicationController
  include FirstSetupPages
  include Assistant::ConnectionAnswers

  without_authorization "the first setup's connection test, on a database with no profile yet", only: :create

  before_action :refuse_without_the_setup_code
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { rate_limited }

  def create
    values = params.expect(setup: [ Installation::Assistant.param_key => Installation::Assistant.fields ])
    step = Installation::Assistant.for_setup.assign(values.fetch(Installation::Assistant.param_key, {}))
    answer_connection_test(step.setting)
  end
end
