# frozen_string_literal: true

# Staging takes main by itself after a merge. When main carries a migration
# that needs the app stopped, the card also says how its rehearsal on
# production's data went.
class Views::Admin::Deliveries::Cards::Staging < Views::Admin::Deliveries::Cards::Base
  private

  def icon = "fa-flask"
  def sync_tone = MAIN_LOOKS.fetch(@pipeline.sync(@environment)).tone

  def facts
    fact(:version) { version }
    fact(:deployed) { deployed }
    fact(:sync) { against_main }
    fact(:health) { health }
    fact(:last) { last } if attempt
    fact(:rehearsal) { rehearsal } if @pipeline.held(@pipeline.production).any?
  end

  def rehearsal
    record = @environment.rehearsal(@pipeline.head.sha)
    if record.nil?
      render Components::StatusBadge.new(tone: :neutral, label: t("admin.deployment.rehearsal.none"))
    elsif record.succeeded?
      render Components::StatusBadge.new(tone: :good, label: t("admin.deployment.rehearsal.passed_short", version: record.short))
      span(class: "deployment__attempt") do
        plain t("admin.deployment.rehearsal.timings", migration: t("admin.deployment.seconds", count: record.migration_seconds.to_i),
                                                      downtime: t("admin.deployment.seconds", count: record.downtime_seconds.to_i))
      end
    else
      render Components::StatusBadge.new(tone: :critical, label: t("admin.deployment.rehearsal.undone_short", version: record.short))
      span(class: "deployment__attempt") { record.description.delete_prefix("undone:").strip }
    end
  end

  def actions
    render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :deploy, destination: "staging"), icon: "fa-rocket",
                                      label: t("admin.deployment.actions.deploy_main"), turbo_stream: true)
  end
end
