# frozen_string_literal: true

# A destination booting the version it runs again.
class Views::Admin::Deliveries::Modals::Restart < Views::Admin::Deliveries::Modals::Base
  private

  def body(form)
    form.hidden_field :destination, value: @press.destination
    line { t("admin.deployment.modals.restart.line", destination: destination_name, version: environment&.short_version) }
  end
end
