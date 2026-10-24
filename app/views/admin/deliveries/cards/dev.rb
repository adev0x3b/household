# frozen_string_literal: true

# Dev runs a branch under test, so its card is about that branch: where it
# stands, its pull request, and whether it can merge from here. Nothing of
# main's reaches dev by itself.
class Views::Admin::Deliveries::Cards::Dev < Views::Admin::Deliveries::Cards::Base
  BRANCH_LOOKS = {
    head: Components::StatusLook.new(tone: :good, icon: "fa-check"),
    behind: Components::StatusLook.new(tone: :warning, icon: "fa-arrow-down"),
    merged: Components::StatusLook.new(tone: :neutral, icon: "fa-code-merge"),
    gone: Components::StatusLook.new(tone: :neutral, icon: "fa-xmark"),
    unknown: Components::StatusLook.new(tone: :neutral, icon: "fa-question")
  }.freeze

  private

  def icon = "fa-code-branch"
  def sync_tone = BRANCH_LOOKS.fetch(@pipeline.sync(@environment)).tone

  def facts
    fact(:branch) { branch }
    fact(:pull_request) { pull_request } if @environment.branch && @pipeline.sync(@environment) != :merged
    fact(:version) { version }
    fact(:data) { data } if @environment.record
    if @environment.stopped?
      fact(:stopped) { deployed }
    else
      fact(:deployed) { deployed }
      fact(:health) { health }
    end
    fact(:last) { last } if attempt
  end

  def branch
    state = @pipeline.sync(@environment)
    if (name = @environment.branch)
      a(href: Deployment.github_url("tree", name), class: "report-mono", target: "_blank", rel: "noopener noreferrer") { name }
    elsif @environment.record
      plain t("admin.deployment.environment.some_branch")
    else
      return plain(t("admin.deployment.environment.nothing"))
    end
    render BRANCH_LOOKS.fetch(state).badge(label: t("admin.deployment.environment.branch_states.#{state}", count: @pipeline.behind_by(@environment)))
  end

  # The branch's open pull request and whether it can merge from here.
  def pull_request
    pull = @pipeline.pull_request(@environment)
    return plain(t("admin.deployment.environment.no_pull_request")) if pull.nil?

    a(href: pull.html_url, target: "_blank", rel: "noopener noreferrer") { "##{pull.number}" }
    span(class: "deployment__commit-title") { pull.title }
    render Views::Admin::Deliveries::MergeBadge.new(state: @pipeline.merge_state(@environment))
  end

  def data
    render Components::StatusBadge.new(tone: :neutral, icon: @environment.fresh? ? "fa-seedling" : "fa-clock-rotate-left",
                                       label: t("admin.deployment.environment.data_#{@environment.fresh? ? "fresh" : "kept"}"))
  end

  def actions
    render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :preview), icon: "fa-rocket", label: t("admin.deployment.actions.preview"), turbo_stream: true)
    return unless @pipeline.merge_state(@environment) == :ready

    render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :merge), icon: "fa-code-merge", label: t("admin.deployment.actions.merge"), turbo_stream: true)
  end

  # Stopping it while it runs; the pull request on GitHub, or where to open
  # one when the branch has none and isn't on main yet.
  def own_actions = [ *stop_action, *pull_request_action ]

  def stop_action
    return [] unless @environment.running?

    [ Components::Action.new(href: new_admin_delivery_request_path(kind: :stop), icon: "fa-power-off", label: t("admin.deployment.actions.stop"), turbo_stream: true) ]
  end

  def pull_request_action
    name = @environment.branch
    return [] if name.nil? || @pipeline.sync(@environment) == :merged

    if (pull = @pipeline.pull_request(@environment))
      [ Components::Action.new(href: pull.html_url, icon: "fa-code-pull-request", label: t("admin.deployment.actions.open_pull_request", number: pull.number)) ]
    else
      [ Components::Action.new(href: Deployment.github_url("compare", "#{Delivery::Pipeline::BRANCH}...#{name}?expand=1"),
                               icon: "fa-code-pull-request", label: t("admin.deployment.actions.open_compare")) ]
    end
  end
end
