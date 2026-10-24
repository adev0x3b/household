# frozen_string_literal: true

# What this copy says about itself renders with the page; the pipeline
# arrives in frames of its own, so the page still says what this copy runs
# when GitHub can't be reached. The one thing it asks GitHub is whether
# deploys are frozen, for the top bar's switch. A self-hosted copy has no
# pipeline: its page is this copy alone, and whether a newer release is out
# as the daily check last found it, so the page itself never waits on GitHub.
class Admin::DeploymentsController < Admin::BaseController
  def show
    checks = Deployment::Checks.run
    return render_page(self_hosted(checks)) if Deployment.self_hosted?

    github = Delivery::Github.configured?
    render_page Views::Admin::Deployments::Show.new(github: github, frozen: (frozen if github), checks: checks)
  end

  private

  def self_hosted(checks)
    release = Deployment.release
    Views::Admin::Deployments::SelfHosted.new(checks: checks, release: release, update: Deployment::Update.for(release),
                                              checking: Platform.release_check?)
  end

  # Nil when GitHub can't say, and the top bar has no switch.
  def frozen
    Delivery::Github.frozen?
  rescue Delivery::Github::Error => e
    Rails.error.report(e, handled: true, context: { asked: :frozen })
    nil
  end
end
