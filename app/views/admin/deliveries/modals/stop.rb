# frozen_string_literal: true

# Stopping dev: what stops, what is kept, and that only a preview starts it again.
class Views::Admin::Deliveries::Modals::Stop < Views::Admin::Deliveries::Modals::Base
  private

  def body(_form)
    unless dev.running?
      hint { t("admin.deployment.modals.stop.not_running", destination: destination_name) }
      return
    end

    line { t("admin.deployment.modals.stop.runs", branch: some_branch, version: dev.short_version) }
    hint { t("admin.deployment.modals.stop.line", destination: destination_name) }
  end
end
