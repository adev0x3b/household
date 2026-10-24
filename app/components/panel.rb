# frozen_string_literal: true

# A part of a page that always shows, such as a form's group of settings:
# a title, an optional hint, then its content. A part that folds and says
# its result in its header is a Components::Disclosure, on the same surface.
#
#   render Components::Panel.new(title: t("…"), hint: t("…")) { … }
class Components::Panel < Components::Base
  def initialize(title:, hint: nil, id: nil, data: {})
    @title = title
    @hint = hint
    @id = id
    @data = data
  end

  def view_template(&)
    section(id: @id, class: "panel", data: @data) do
      h2(class: "panel__title") { @title }
      p(class: "report-hint") { @hint } if @hint
      div(class: "panel__body", &)
    end
  end
end
