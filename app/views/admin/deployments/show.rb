# frozen_string_literal: true

# What this copy says about itself renders with the page, and the pipeline
# fills two frames once the page is up, so a slow GitHub holds nothing back.
class Views::Admin::Deployments::Show < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  # github: whether a deploy token is set (the pipeline's frames and actions
  # need it); frozen: whether deploys are frozen, nil when GitHub couldn't
  # say; checks: what this copy found about itself (Deployment::Checks).
  def initialize(github:, frozen:, checks:)
    @github = github
    @frozen = frozen
    @checks = checks
  end

  def page_title = t("admin.deployment.title")

  # The pipeline's own switch, deploys frozen or not. None without the
  # token, or when GitHub can't say which: the page still shows this copy.
  def navbar_controls
    return if @frozen.nil?

    switch = Components::Action.new(href: routes.new_admin_delivery_request_path(kind: @frozen ? :unfreeze : :freeze), icon: "fa-snowflake",
                                    label: t("admin.deployment.actions.#{@frozen ? "unfreeze" : "freeze"}"), turbo_stream: true, active: @frozen)
    Components::PageControls.new(actions: [ switch ])
  end

  def view_template
    div(class: "report-page deployment") do
      render Components::PageHeader.new(title: t("admin.deployment.title"))
      p(class: "report-hint") { t("admin.deployment.hint") }
      no_token unless @github
      turbo_frame_tag(Views::Admin::Deployments::ThisCopy::FRAME_ID) { render Views::Admin::Deployments::ThisCopy.new(checks: @checks) }
      if @github
        console_frame
        metrics_frame
      end
    end
  end

  private

  # The token is set on the admin's settings page.
  def no_token
    render Components::Notice.new(tone: :neutral) do
      p do
        plain t("admin.deployment.no_token")
        whitespace
        a(href: admin_settings_path) { t("admin.deployment.no_token_link") }
      end
    end
  end

  # The pipeline, loaded once the page is up and polled while something runs.
  def console_frame
    turbo_frame_tag(Views::Admin::Deliveries::Console::FRAME_ID, src: console_admin_delivery_path, loading: :lazy, refresh: :morph, target: "_top") do
      loading(t("admin.deployment.console.loading"))
    end
  end

  def metrics_frame
    turbo_frame_tag(Views::Admin::Deliveries::Metrics::FRAME_ID, src: metrics_admin_delivery_path, loading: :lazy, refresh: :morph, target: "_top") do
      loading(t("admin.deployment.metrics.loading"))
    end
  end

  def loading(text)
    p(class: "report-hint deployment__loading", aria: { busy: "true" }) do
      render Components::Icon.new("fa-spinner fa-spin")
      whitespace
      plain text
    end
  end
end
