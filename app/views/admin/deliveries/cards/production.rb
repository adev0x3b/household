# frozen_string_literal: true

# Production only moves by a press, so its card carries the actions nothing
# else has: promoting what staging runs, rolling back, and releasing a
# version that needs the app stopped.
class Views::Admin::Deliveries::Cards::Production < Views::Admin::Deliveries::Cards::Base
  private

  def icon = "fa-house"
  def sync_tone = MAIN_LOOKS.fetch(@pipeline.sync(@environment)).tone

  def facts
    fact(:version) { version }
    fact(:deployed) { deployed }
    fact(:sync) { against_main }
    fact(:health) { health }
    fact(:last) { last } if attempt
  end

  def actions
    candidate = @pipeline.staging.version
    return if candidate.blank? || candidate == @environment.version

    render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :deploy, destination: "production", version: candidate), icon: "fa-arrow-up",
                                      label: t("admin.deployment.actions.promote", version: candidate.first(7)), turbo_stream: true)
  end

  def own_actions
    actions = [ Components::Action.new(href: new_admin_delivery_request_path(kind: :rollback), icon: "fa-rotate-left", label: t("admin.deployment.actions.rollback"), turbo_stream: true) ]
    if @pipeline.held(@environment).any?
      actions << Components::Action.new(href: new_admin_delivery_request_path(kind: :release, version: @pipeline.head.sha), icon: "fa-hand",
                                        label: t("admin.deployment.actions.release"), turbo_stream: true, danger: true)
    end
    actions
  end
end
