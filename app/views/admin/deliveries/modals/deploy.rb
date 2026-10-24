# frozen_string_literal: true

# Main's version to a destination: what it gains, and, for production,
# that staging already runs it. A version whose migrations need the app
# stopped is refused for production and pointed at a release; staging
# rehearses it and the demo takes it behind its maintenance page, which
# the modal says.
class Views::Admin::Deliveries::Modals::Deploy < Views::Admin::Deliveries::Modals::Base
  private

  def body(form)
    form.hidden_field :destination, value: @press.destination
    form.hidden_field :version, value: @press.version
    same_as_staging if @press.gated? && @pipeline.staging.version == @press.version
    if @press.blocked?
      held
    elsif @press.held.any?
      render Components::Notice.new(tone: :action) { p { t("admin.deployment.modals.deploy.stopped.#{@press.destination}", count: @press.held.size) } }
    end
    ships(@press.gained)
  end

  def same_as_staging
    line do
      render Components::Icon.new("fa-circle-check")
      whitespace
      plain t("admin.deployment.modals.deploy.same_as_staging")
    end
  end

  def held
    render Components::Notice.new(tone: :critical) do
      p { t("admin.deployment.modals.deploy.held", count: @press.held.size) }
      ul { @press.held.each { |path| li(class: "report-mono") { path } } }
      p { a(href: new_admin_delivery_request_path(kind: :release, version: @press.version), data: { turbo_stream: true }) { t("admin.deployment.actions.release") } }
    end
  end
end
