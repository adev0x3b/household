# frozen_string_literal: true

# Main's head, whether CI passed it and built its image, and the commits
# production doesn't have yet, folded so the card stays short.
class Views::Admin::Deliveries::MainCard < Views::Base
  CI_LOOKS = {
    none: Components::StatusLook.new(tone: :neutral),
    running: Components::StatusLook.new(tone: :warning).busy,
    passed: Components::StatusLook.new(tone: :good),
    failed: Components::StatusLook.new(tone: :critical)
  }.freeze

  def initialize(pipeline:)
    @pipeline = pipeline
  end

  def view_template
    render Components::Panel.new(title: t("admin.deployment.pipeline.title"), hint: t("admin.deployment.pipeline.hint")) do
      head
      pending
    end
  end

  private

  def head
    commit = @pipeline.head
    div(class: "deployment__commit deployment__commit--head") do
      a(href: commit.html_url, class: "report-mono", target: "_blank", rel: "noopener noreferrer") { commit.short }
      span(class: "deployment__commit-title") { commit.title }
      span(class: "deployment__commit-meta") { t("admin.deployment.pipeline.by", author: commit.author, time: time_ago(commit.committed_at)) }
      div(class: "deployment__badges") do
        ci_badge
        image_badge
      end
      render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :ci), icon: "fa-play", label: t("admin.deployment.actions.ci"), turbo_stream: true)
    end
  end

  def ci_badge
    state = @pipeline.ci_state
    label = t("admin.deployment.pipeline.ci.#{state}")
    badge = CI_LOOKS.fetch(state).badge(label: label)
    if (run = @pipeline.ci)
      a(href: run.html_url, target: "_blank", rel: "noopener noreferrer", class: "deployment__badge-link") { render badge }
    else
      render badge
    end
  end

  def image_badge
    return unless @pipeline.ci_state == :passed

    built = @pipeline.image_built?
    render Components::StatusBadge.new(tone: built ? :good : :warning, icon: "fa-box", label: t("admin.deployment.pipeline.image.#{built ? "built" : "missing"}"))
  end

  # What production doesn't have yet, folded; open when there is something.
  def pending
    commits = @pipeline.pending(@pipeline.production)
    held = @pipeline.held(@pipeline.production)
    if commits.empty?
      p(class: "report-hint") { t("admin.deployment.pipeline.pending.none") }
      return
    end

    render Components::Disclosure.new(key: "deployment-pending-#{@pipeline.head.short}", title: t("admin.deployment.pipeline.pending.title"), open: true,
                                      result: -> { plain t("admin.deployment.pipeline.pending.count", count: commits.size) }) do
      if held.any?
        p(class: "report-flag deployment__held") do
          render Components::Icon.new("fa-triangle-exclamation")
          whitespace
          plain t("admin.deployment.pipeline.held", count: held.size)
        end
      end
      ul(class: "report-rows") do
        commits.reverse_each do |commit|
          li(class: "deployment__commit") do
            a(href: commit.html_url, class: "report-mono", target: "_blank", rel: "noopener noreferrer") { commit.short }
            span(class: "deployment__commit-title") { commit.title }
            span(class: "deployment__commit-meta") { time_ago(commit.committed_at) }
          end
        end
      end
    end
  end
end
