# frozen_string_literal: true

# What this copy says about itself, with nothing asked of GitHub. The card
# takes the tone of the worst answer.
class Views::Admin::Deployments::ThisCopy < Views::Base
  FRAME_ID = "deployment-this-copy"

  # checks: what this copy found when it looked at itself (Deployment::Checks).
  def initialize(checks:)
    @checks = checks
    @release = Deployment.release
  end

  def view_template
    render Components::Report::StatusCard.new(tone: tone, compact: true) do |card|
      card.head do
        render Components::StatusBadge.new(tone: known? ? :good : :neutral, icon: "fa-rocket", label: badge_label)
        span(class: "report-tag") { t("admin.deployment.this_copy") }
        card.time { t("admin.deployment.booted", time: time_ago_in_words(Deployment.booted_at)) }
      end
      ul(class: "report-rows deployment__facts") do
        fact(:version) { version }
        fact(:environment) { environment }
        fact(:ruby) { RUBY_VERSION }
        fact(:rails) { Rails.version }
        fact(:booted) { l(Deployment.booted_at, format: :short) }
        fact(:database) { check(@checks.database, "db") }
        fact(:worker) { check(@checks.worker, "worker") }
      end
    end
  end

  private

  # A release is named by its version, anything else by its commit.
  def known? = @release.present? || Deployment.versioned?

  def badge_label
    return t("admin.deployment.no_version") unless known?

    t("admin.deployment.version_badge", version: @release&.version || Deployment.short_version)
  end

  def environment
    if Deployment.deployed? then t("admin.deployment.destinations.#{Deployment.destination}")
    elsif Deployment.self_hosted? then t("admin.deployment.self_hosted")
    else Rails.env
    end
  end

  def fact(key, &)
    li do
      span(class: "deployment__label") { t("admin.deployment.facts.#{key}") }
      span(class: "deployment__value", &)
    end
  end

  def version
    return release_version if @release
    return plain(t("admin.deployment.no_version")) unless Deployment.versioned?

    a(href: Deployment.commit_url, class: "report-mono", target: "_blank", rel: "noopener noreferrer") { Deployment.short_version }
    span(class: "report-flag") { t("admin.deployment.uncommitted") } if Deployment.uncommitted?
  end

  # The release's notes say what it holds and which commit it was cut from.
  def release_version
    a(href: @release.notes_url, class: "report-mono", target: "_blank", rel: "noopener noreferrer") { @release.version }
  end

  # true or false, or nil where the check can't be made (no Solid Queue here).
  def check(ok, what)
    if ok.nil?
      render Components::StatusBadge.new(tone: :neutral, label: t("admin.deployment.checks.#{what}_unknown"))
    else
      render Components::StatusBadge.new(tone: ok ? :good : :critical,
                                         label: t("admin.deployment.checks.#{what}_#{ok ? "ok" : "down"}", minutes: @checks.worker_window.in_minutes.to_i))
    end
  end

  def tone
    return :critical unless @checks.database
    return :warning if @checks.worker == false
    return :neutral unless known?

    :good
  end
end
