# frozen_string_literal: true

# A form that sends itself as its fields change (auto_submit_controller.js):
# a search as the reader types, or a choice as soon as it is picked (by
# keyboard, once the reader presses Enter or leaves the select).
#
# A search needs `turbo_frame:`, a frame outside the form that holds only
# the results. The answer replaces that frame and never the field, so the
# focus, and whatever is typed while a request is out, are kept. The form
# must never sit inside the frame it targets, nor the page around it be
# replaced or morphed. With `turbo_action: "replace"` beside the frame the
# address follows the search without the page being drawn again; a choice
# with `turbo_action: "replace"` alone visits the whole page again.
class Components::AutoSubmitForm < Components::Base
  def initialize(url:, dom_id:, method: :get, html_class: nil, turbo_frame: nil, turbo_action: nil)
    @url = url
    @dom_id = dom_id
    @method = method
    @html_class = html_class
    @turbo_frame = turbo_frame
    @turbo_action = turbo_action
  end

  def view_template(&)
    form(action: @url, method: @method, class: @html_class, data: form_data) do
      yield(self) if block_given?
    end
  end

  def search_field(name:, value: nil, placeholder: nil, html_class: nil)
    raise ArgumentError, "search_field needs turbo_frame: (a results-only frame outside the form)" unless @turbo_frame

    input(
      type: "search",
      id: field_id(name),
      name: name,
      value: value,
      placeholder: placeholder,
      class: html_class,
      autocomplete: "off",
      aria: { label: placeholder },
      data: { action: "input->auto-submit#search" }
    )
  end

  # `label`: its name for assistive technology when no visible label says it.
  def select_field(name:, html_class: nil, label: nil, &block)
    select(
      id: field_id(name),
      name: name,
      class: html_class,
      aria: { label: label },
      data: { action: "change->auto-submit#choose keydown->auto-submit#keydown keyup->auto-submit#keyup blur->auto-submit#leave" },
      &block
    )
  end

  private

  def form_data
    data = { controller: "auto-submit", action: "submit->auto-submit#cancel" }
    data[:turbo_frame] = @turbo_frame if @turbo_frame
    data[:turbo_action] = @turbo_action if @turbo_action
    data
  end

  def field_id(name) = "#{@dom_id}_#{name}"
end
