# frozen_string_literal: true

# What a chart, a table or a list shows when it has nothing to show: one
# muted line, with an icon that says what would be there, instead of empty
# axes or an empty table. `id:` names a line a stream takes away when the
# first item arrives.
class Components::EmptyState < Components::Base
  def initialize(message:, icon:, id: nil)
    @message = message
    @icon = icon
    @id = id
  end

  def view_template
    p(id: @id, class: "empty-state") do
      render Components::Icon.new(@icon)
      span { @message }
    end
  end
end
