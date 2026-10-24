# frozen_string_literal: true

# Whether a newer release is out, as the daily check last found it. The
# card asks for the admin's hand only when there is something to update to.
class Views::Admin::Deployments::UpdateCard < Views::Base
  LOOKS = {
    off: Components::StatusLook.new(tone: :neutral, icon: "fa-bell-slash"),
    waiting: Components::StatusLook.new(tone: :neutral, icon: "fa-clock"),
    current: Components::StatusLook.new(tone: :good),
    available: Components::StatusLook.new(tone: :warning, icon: "fa-arrow-up")
  }.freeze

  # update: the last check's answer (Deployment::Update), nil before the
  # first; checking: whether the admin allows the check at all.
  def initialize(update:, checking:)
    @update = update
    @checking = checking
  end

  def view_template
    look = LOOKS.fetch(state)
    render Components::Report::StatusCard.new(tone: look.tone, action: state == :available, compact: true) do |card|
      card.head do
        render look.badge(label: t("admin.deployment.update.badges.#{state}", version: @update&.newest&.version))
        span(class: "report-tag") { t("admin.deployment.update.tag") }
        card.time { t("admin.deployment.update.checked", time: time_ago_in_words(@update.checked_at)) } if checked?
      end
      card.now { says }
    end
  end

  private

  def checked? = @checking && @update.present?

  def state
    if !@checking then :off
    elsif @update.nil? then :waiting
    elsif @update.available? then :available
    else :current
    end
  end

  def says
    case state
    when :off
      plain t("admin.deployment.update.off")
      whitespace
      a(href: admin_settings_path) { t("admin.deployment.update.off_link") }
    when :available
      plain t("admin.deployment.update.available")
      whitespace
      a(href: @update.newest.notes_url, target: "_blank", rel: "noopener noreferrer") { t("admin.deployment.update.notes", version: @update.newest.version) }
    when :waiting then plain t("admin.deployment.update.waiting")
    else plain t("admin.deployment.update.current", version: @update.running.version)
    end
  end
end
