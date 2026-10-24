# frozen_string_literal: true

# /admin/deployment on a copy someone runs themselves: no pipeline delivers
# it, so the page is what this copy says about itself, and an update is a
# command on the machine rather than a press here.
class Views::Admin::Deployments::SelfHosted < Views::Base
  # checks: what this copy found about itself (Deployment::Checks);
  # release: the release it runs, nil when it runs something else, which
  # no check can compare; update: the daily check's last answer
  # (Deployment::Update), nil before the first; checking: whether the
  # admin allows that check.
  def initialize(checks:, release:, update:, checking:)
    @checks = checks
    @release = release
    @update = update
    @checking = checking
  end

  def page_title = t("admin.deployment.title")

  def view_template
    div(class: "report-page deployment") do
      render Components::PageHeader.new(title: t("admin.deployment.title"))
      p(class: "report-hint") do
        plain t("admin.deployment.self_hosted_hint")
        whitespace
        code(class: "deployment__command") { Deployment::UPDATE_COMMAND }
      end
      render Views::Admin::Deployments::UpdateCard.new(update: @update, checking: @checking) if @release
      render Views::Admin::Deployments::ThisCopy.new(checks: @checks)
    end
  end
end
