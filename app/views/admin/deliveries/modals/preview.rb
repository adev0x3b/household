# frozen_string_literal: true

# The branch dev runs is prefilled, so previewing its newest commit is one
# press; preview_form_controller.js ticks "fresh data" for any other branch.
class Views::Admin::Deliveries::Modals::Preview < Views::Admin::Deliveries::Modals::Base
  private

  def body(form)
    current = dev.branch
    hint { t("admin.deployment.modals.preview.help") }
    line do
      if dev.version
        plain t("admin.deployment.modals.preview.runs", branch: some_branch, version: dev.short_version)
      else
        plain t("admin.deployment.modals.preview.nothing")
      end
    end
    div(class: "deployment-modal__fields", data: { controller: "preview-form", preview_form_current_value: current.to_s }) do
      render Components::Field.new(label: t("admin.deployment.modals.preview.branch_label"), control_id: "press_ref") do
        form.text_field :ref, value: @press.ref || current, list: "deployment-branches", class: "input is-medium", autocomplete: "off",
                              autocapitalize: "off", spellcheck: "false", required: true, data: { preview_form_target: "branch", action: "input->preview-form#changed" }
        datalist(id: "deployment-branches") { @pipeline.branches.each { |name| option(value: name) } }
      end
      div(class: "field") do
        label(class: "deployment-modal__check", for: "press_fresh") do
          form.check_box :fresh, { checked: @press.fresh, data: { preview_form_target: "fresh" } }, "1", "0"
          span { t("admin.deployment.modals.preview.fresh_label") }
        end
        p(class: "help") { t("admin.deployment.modals.preview.fresh_help") }
      end
    end
  end
end
