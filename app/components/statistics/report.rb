# frozen_string_literal: true

# One report on a dashboard: a heading, an optional one-line explanation of
# how its numbers are defined, and whatever the block renders (usually a
# chart followed by a table). The surface is darker than Components::Card
# on purpose, because the chart palette is validated for ≥ 3:1 contrast
# against $stat-surface.
class Components::Statistics::Report < Components::Base
  def initialize(title:, icon:, description: nil, dom_id: nil)
    @title = title
    @icon = icon
    @description = description
    @dom_id = dom_id
  end

  def view_template(&)
    section(id: @dom_id, class: "stat-report", aria: { labelledby: heading_id }) do
      header(class: "stat-report__header") do
        h2(id: heading_id, class: "stat-report__title") do
          render Components::Icon.new(@icon)
          span { @title }
        end
        p(class: "stat-report__description") { @description } if @description
      end
      div(class: "stat-report__body", &)
    end
  end

  private

  def heading_id = "#{@dom_id || @title.parameterize}-heading"
end
