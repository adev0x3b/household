# frozen_string_literal: true

# The demo: main after a merge, right after staging took it, on data of its
# own that starts over every night (config/deploy.demo.yml). Where it stands
# against main; its first action deploys main's head.
class Views::Admin::Deliveries::Cards::Demo < Views::Admin::Deliveries::Cards::Base
  private

  def icon = "fa-users"
  def sync_tone = MAIN_LOOKS.fetch(@pipeline.sync(@environment)).tone

  def facts
    fact(:version) { version }
    fact(:deployed) { deployed }
    fact(:sync) { against_main }
    fact(:health) { health }
    fact(:last) { last } if attempt
  end

  def actions
    render Components::ItemAction.new(href: new_admin_delivery_request_path(kind: :deploy, destination: "demo"), icon: "fa-rocket",
                                      label: t("admin.deployment.actions.deploy_main"), turbo_stream: true)
  end
end
