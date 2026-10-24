# frozen_string_literal: true

# A run's status as a pill: Running, Paused, Finished, Crashed.
class Views::Assistant::Evals::RunBadge < Views::Base
  def initialize(status:)
    @status = status.to_sym
  end

  def view_template
    render Views::Assistant::Evals::Status.run(@status).badge(label: t("assistant.evals.run.status.#{@status}"))
  end
end
