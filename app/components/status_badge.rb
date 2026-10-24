# frozen_string_literal: true

# How something stands, as a small pill: a lab flag, a supply running low,
# an upload, a deploy, an eval run. The tone's colour always comes with an
# icon and a word, never colour alone. `icon:` replaces the tone's own (a
# spinner for "running", a pause sign); `title:` explains it on hover. A
# kind of status with a table of looks draws it through StatusLook#badge.
class Components::StatusBadge < Components::Base
  def initialize(tone:, label:, icon: nil, title: nil)
    @look = Components::StatusLook.new(tone:, icon:)
    @label = label
    @title = title
  end

  def view_template
    span(class: "status-badge status-badge--#{@look.tone}", title: @title) do
      render Components::Icon.new(@look.icon)
      span { @label }
    end
  end
end
