# frozen_string_literal: true

# An item as a card: a header, a body (plain, scrolling, or folded behind
# its summary) and its round action buttons.
class Components::Card < Components::Base
  SIZES = %i[small default large].freeze

  def initialize(dom_id: nil, size: :default)
    raise ArgumentError, "unknown card size: #{size.inspect}" unless SIZES.include?(size)

    @dom_id = dom_id
    @size = size
  end

  def view_template
    div(id: @dom_id, class: card_classes) { yield(self) if block_given? }
  end

  def header(&block)
    div(class: "card__header", &block)
  end

  def body(&block)
    div(class: "card__body", &block)
  end

  def scrollable_body(&block)
    div(class: "card__body card__body--scroll", &block)
  end

  # `summary` is always visible; the block content is hidden until the
  # summary is pressed. Requires the `card-toggle` Stimulus controller.
  def collapsible_body(summary:, expanded: false, &block)
    div(class: "card__body card__body--collapsible", data: { controller: "card-toggle" }) do
      button(
        type: "button",
        class: "card__summary",
        aria: { expanded: expanded.to_s },
        data: { card_toggle_target: "trigger", action: "click->card-toggle#toggle" }
      ) do
        span { summary }
        render Components::Icon.new("fa-chevron-down", class: "card__chevron")
      end

      div(class: "card__panel", hidden: !expanded, data: { card_toggle_target: "panel" }, &block)
    end
  end

  def actions(&block)
    div(class: "card__actions", &block)
  end

  private

  def card_classes
    classes = "card"
    classes += " card--#{@size}" unless @size == :default
    classes
  end
end
