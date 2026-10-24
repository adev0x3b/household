# frozen_string_literal: true

# The element one Components::Action is pressed through, the same wherever
# it is drawn; the place that draws it gives its look and what it shows
# through the attributes and the block.
class Components::ActionControl < Components::Base
  include Phlex::Rails::Helpers::ButtonTo

  def initialize(action, data: {}, **attributes)
    @action = action
    @data = action.data.merge(data)
    @attributes = attributes
  end

  # A press that changes something is a link Turbo sends with its method,
  # from a form it makes outside the page's own, so the press works inside a
  # form too (a secret's field with the trash beside it). A download is a
  # real form, posted outside Turbo. An action without a link is a button a
  # script runs.
  def view_template(&)
    if @action.download
      button_to(@action.href, method: :post, **@attributes, data: @data, form_class: "action-control__form", form: { data: { turbo: false } }, &)
    elsif @action.href
      a(href: @action.href, **@attributes, data: link_data, &)
    else
      button(type: "button", **@attributes, data: @data, &)
    end
  end

  private

  def link_data
    { turbo_stream: (true if @action.turbo_stream), turbo_method: @action.verb, turbo_confirm: @action.confirm }.compact.merge(@data)
  end
end
