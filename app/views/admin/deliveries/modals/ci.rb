# frozen_string_literal: true

# CI by hand on a branch: main unless another is typed.
class Views::Admin::Deliveries::Modals::Ci < Views::Admin::Deliveries::Modals::Base
  private

  def body(form)
    hint { t("admin.deployment.modals.ci.help") }
    render Components::Field.new(label: t("admin.deployment.modals.ci.ref_label"), control_id: "press_ref") do
      form.text_field :ref, value: @press.ref, class: "input is-medium", autocomplete: "off", spellcheck: "false"
    end
  end
end
