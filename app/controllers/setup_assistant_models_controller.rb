# frozen_string_literal: true

# The model list on the first setup's assistant step, loaded when the step
# opens and again when another provider is picked. Open, like the setup
# itself, only to a browser that gave the setup code, and limited by
# address, since every load asks the provider.
class SetupAssistantModelsController < ApplicationController
  include FirstSetupPages
  include Assistant::ConnectionAnswers

  without_authorization "the first setup's model list, on a database with no profile yet", only: :show

  before_action :refuse_without_the_setup_code
  rate_limit to: 20, within: 1.minute, only: :show, with: -> { rate_limited }

  def show
    answer_model_list(params[:provider])
  end
end
