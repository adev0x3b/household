# frozen_string_literal: true

# One destination on the console. The card takes the tone of the worst of
# its facts, so the destination that needs a look stands out among four.
class Views::Admin::Deliveries::Cards::Base < Views::Base
  # The card for a Delivery::Environment, by its name.
  def self.for(environment)
    { "dev" => Views::Admin::Deliveries::Cards::Dev, "staging" => Views::Admin::Deliveries::Cards::Staging,
      "demo" => Views::Admin::Deliveries::Cards::Demo, "production" => Views::Admin::Deliveries::Cards::Production }.fetch(environment.name)
  end

  # Where staging, the demo or production stands against main.
  MAIN_LOOKS = {
    head: Components::StatusLook.new(tone: :good, icon: "fa-check"),
    behind: Components::StatusLook.new(tone: :warning, icon: "fa-arrow-down"),
    rolled_back: Components::StatusLook.new(tone: :warning, icon: "fa-rotate-left"),
    ahead: Components::StatusLook.new(tone: :warning, icon: "fa-arrow-up"),
    unknown: Components::StatusLook.new(tone: :neutral, icon: "fa-question")
  }.freeze

  def initialize(pipeline:, environment:)
    @pipeline = pipeline
    @environment = environment
  end

  def view_template
    render Components::Report::StatusCard.new(tone: tone, id: "deployment-#{name}", data: { destination: name }) do |card|
      card.head do
        render Components::StatusBadge.new(tone: @environment.here? ? :good : :neutral, icon: icon, label: t("admin.deployment.destinations.#{name}"))
        span(class: "report-tag") { t("admin.deployment.this_copy") } if @environment.here?
        card.time { t("admin.deployment.environment.#{@environment.stopped? ? "stopped_ago" : "deployed_ago"}", time: time_ago_in_words(@environment.deployed_at)) } if @environment.record
        div(class: "deployment__actions") do
          actions
          render Components::ItemMenu.new(label: t("admin.deployment.actions.more"), actions: menu_actions)
        end
      end
      ul(class: "report-rows deployment__facts") { facts }
    end
  end

  private

  def name = @environment.name

  def icon = raise(NotImplementedError)
  def facts = raise(NotImplementedError)
  # At most two Components::ItemAction, the ones used most.
  def actions = nil
  # The subclass's own actions behind "more", between the restart and opening it.
  def own_actions = []
  # The tone of how it stands against what feeds it.
  def sync_tone = raise(NotImplementedError)

  def menu_actions = [ *restart_action, *own_actions, *open_action ]

  # A stopped destination has nothing to restart: a preview starts it.
  def restart_action
    return [] if @environment.stopped?

    [ Components::Action.new(href: new_admin_delivery_request_path(kind: :restart, destination: name), icon: "fa-arrow-rotate-right",
                             label: t("admin.deployment.actions.restart"), turbo_stream: true) ]
  end

  # Where it can be opened, when its address is configured (Deployment.url).
  def open_action
    return [] unless @environment.url

    [ Components::Action.new(href: @environment.url, icon: "fa-arrow-up-right-from-square",
                             label: t("admin.deployment.environment.open", name: t("admin.deployment.destinations.#{name}"))) ]
  end

  def tone
    worst = [ sync_tone, health_tone, (attempt&.failed? ? :warning : nil) ].compact
    %i[critical warning neutral good].find { worst.include?(_1) }
  end

  def health_tone
    case @environment.health.ok?
    when true then :good
    when false then :critical
    else :neutral
    end
  end

  def fact(key, &)
    li do
      span(class: "deployment__label") { t("admin.deployment.environment.#{key}") }
      span(class: "deployment__value", &)
    end
  end

  def version
    record = @environment.record
    return plain(t("admin.deployment.environment.nothing")) if record.nil?

    a(href: Deployment.github_url("commit", record.sha), class: "report-mono", target: "_blank", rel: "noopener noreferrer") { record.short }
    span(class: "deployment__commit-title") { @pipeline.commit(record.sha).title }
  end

  def deployed
    record = @environment.record
    return plain(t("admin.deployment.environment.nothing")) if record.nil?

    plain t("admin.deployment.environment.by", time: time_ago(@environment.deployed_at), who: record.requested_by || t("admin.deployment.environment.someone"))
    whitespace
    a(href: record.run_url, target: "_blank", rel: "noopener noreferrer") { t("admin.deployment.environment.run") } if record.run_url
  end

  def health
    state = @environment.health
    title = t("admin.deployment.environment.health_states.unknown_why", name: t("admin.deployment.destinations.#{name}")) if state.ok?.nil?
    render Components::StatusBadge.new(tone: health_tone, icon: ("fa-lock" if state.ok?.nil?),
                                       label: t("admin.deployment.environment.health_states.#{state.key}"), title: title)
  end

  # The newest attempt, when it isn't what runs: held, failed, in progress.
  def attempt
    last = @environment.last
    last if last && last != @environment.record
  end

  def last
    record = attempt
    look = if record.live? then Components::StatusLook.new(tone: :warning).busy
    elsif record.held? then Components::StatusLook.new(tone: :warning, icon: "fa-hand")
    else Components::StatusLook.new(tone: :critical)
    end
    render look.badge(label: "#{record.task} #{record.short}")
    span(class: "deployment__attempt") { record.description.presence || t("admin.deployment.environment.in_progress") }
    a(href: record.run_url, target: "_blank", rel: "noopener noreferrer") { t("admin.deployment.environment.run") } if record.run_url
  end

  def against_main
    state = @pipeline.sync(@environment)
    render MAIN_LOOKS.fetch(state).badge(label: t("admin.deployment.environment.sync_states.#{state}", count: @pipeline.behind_by(@environment)))
  end
end
