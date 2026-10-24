# frozen_string_literal: true

module Deployment
  # Once a day, on a self-hosted copy running a release whose admin allows
  # it, asks whether a newer release is out (Deployment::CheckForUpdate).
  # GitHub not answering is reported as a warning: the next day asks again.
  class UpdateCheckJob < ApplicationJob
    def perform
      release = Deployment.release
      return unless release && Platform.release_check?

      CheckForUpdate.call(release)
    rescue Releases::Error => e
      Rails.error.report(e, handled: true, severity: :warning, context: { job: self.class.name, version: release.version })
    end
  end
end
