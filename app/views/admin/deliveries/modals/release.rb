# frozen_string_literal: true

# A version whose migrations need the app stopped, to production behind
# the maintenance page: how its last rehearsal on production's data went,
# the migrations, what ships, and that every member is told.
class Views::Admin::Deliveries::Modals::Release < Views::Admin::Deliveries::Modals::Base
  private

  def body(form)
    form.hidden_field :version, value: @press.version
    render Components::Notice.new(tone: :action) do
      p do
        strong { t("admin.deployment.modals.release.downtime") }
        whitespace
        plain downtime_line
      end
    end
    if @press.held.any?
      line { t("admin.deployment.modals.release.held", count: @press.held.size) }
      ul(class: "deployment-modal__list") { @press.held.each { |path| li(class: "report-mono") { path } } }
    end
    ships(@press.gained)
    line do
      render Components::Icon.new("fa-bell")
      whitespace
      plain t("admin.deployment.modals.release.members_told")
    end
  end

  # The last rehearsal of this version on production's data, or that there was none.
  def downtime_line
    rehearsal = @press.rehearsal
    if rehearsal&.succeeded?
      t("admin.deployment.modals.release.rehearsed", downtime: t("admin.deployment.seconds", count: rehearsal.downtime_seconds.to_i),
                                                     migration: t("admin.deployment.seconds", count: rehearsal.migration_seconds.to_i))
    elsif rehearsal
      t("admin.deployment.modals.release.undone", reason: rehearsal.description.delete_prefix("undone:").strip)
    else
      t("admin.deployment.modals.release.not_rehearsed")
    end
  end
end
