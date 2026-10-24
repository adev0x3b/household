# frozen_string_literal: true

# One analyte and its reference ranges. Editing it is the top bar's, with
# deleting behind its "more".
class Views::Analytes::Show < Views::Base
  def initialize(analyte:, ranges:, viewer:)
    @analyte = analyte
    @ranges = ranges
    @viewer = viewer
  end

  def page_title = @analyte.name

  def navbar_controls
    policy = Pundit.policy!(@viewer, @analyte)
    actions = []
    if policy.update?
      actions << Components::Action.new(href: routes.edit_analyte_path(@analyte), icon: "fa-pen", label: t("analytes.show.edit"), turbo_stream: true)
    end
    if policy.destroy?
      actions << Components::Action.new(href: routes.analyte_path(@analyte), icon: "fa-trash", label: t("analytes.show.destroy"), method: :delete,
                                        confirm: t("analytes.confirm_destroy"), danger: true)
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "analyte-show") do
      header
      render Views::Analytes::ReferenceRangesList.new(analyte: @analyte, ranges: @ranges)
    end
  end

  private

  def header
    render Components::PageHeader.new(title: @analyte.name, back_href: analytes_path, back_label: t("analytes.show.back"))
  end
end
