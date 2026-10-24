# frozen_string_literal: true

# DORA's four keys, drawn with the dashboards' own tiles so they read like
# every other figure in the app.
class Views::Admin::Deliveries::Metrics < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "deployment-metrics"
  ICONS = { frequency: "fa-rocket", lead_time: "fa-hourglass-half", failure_rate: "fa-triangle-exclamation", recovery_time: "fa-bandage" }.freeze

  # metrics: { frequency:, lead_time:, failure_rate:, recovery_time: } of Reports::Metric; nil when GitHub couldn't be asked.
  def initialize(metrics: nil, error: nil)
    @metrics = metrics
    @error = error
  end

  def view_template
    turbo_frame_tag(FRAME_ID, target: "_top") do
      render Components::Panel.new(title: t("admin.deployment.metrics.title"), hint: t("admin.deployment.metrics.hint")) do
        if @error
          p(class: "deployment__error", role: "alert") { t("admin.deployment.console.error", error: @error) }
        else
          section(class: "statistics__kpis", aria: { label: t("admin.deployment.metrics.title") }) do
            @metrics.each do |key, metric|
              render Components::Statistics::StatTile.new(metric: metric, label: t("admin.deployment.metrics.#{key}.label"), icon: ICONS.fetch(key),
                                                          hint: t("admin.deployment.metrics.#{key}.hint"))
            end
          end
        end
      end
    end
  end
end
