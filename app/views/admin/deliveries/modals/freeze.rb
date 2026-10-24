# frozen_string_literal: true

# Freezing the automatic deploys: main's pushes build and stop there.
class Views::Admin::Deliveries::Modals::Freeze < Views::Admin::Deliveries::Modals::Base
  private

  def body(_form)
    line { t("admin.deployment.modals.freeze.line") }
  end
end
