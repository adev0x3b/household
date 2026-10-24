# frozen_string_literal: true

module Admins
  # Delivers Admins::Alert's notification to every admin, away from
  # the request or job that was failing when it was asked for.
  class AlertJob < ApplicationJob
    def perform(kind, data)
      Profile.admin.joined.find_each do |admin|
        Notifications::Deliver.call(recipient: admin, kind: kind, data: data)
      end
    end

    private

    # An alert that it failed would be one more of this job, failing the
    # same way.
    def alerts_admins_when_failing? = false
  end
end
