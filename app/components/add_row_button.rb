# frozen_string_literal: true

# "Add a value", "Add a step": the quiet button under the rows a form adds
# to one at a time. It asks the nested-fields controller for a new row, or,
# given `href:`, opens the form that adds one.
class Components::AddRowButton < Components::Base
  def initialize(label:, href: nil, data: {})
    @label = label
    @href = href
    @data = data
  end

  def view_template
    if @href
      a(href: @href, class: "add-row-button", data: @data) { content }
    else
      button(type: "button", class: "add-row-button", data: { action: "click->nested-fields#add", **@data }) { content }
    end
  end

  private

  def content
    render Components::Icon.new("fa-plus")
    span { @label }
  end
end
