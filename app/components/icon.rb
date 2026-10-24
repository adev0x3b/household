# frozen_string_literal: true

# A Font Awesome icon, named by its class ("fa-bell", or "fa-spinner fa-spin"
# with its animation). Most icons sit beside words that already say what
# they mean, so a screen reader skips them. An icon that stands for words
# of its own takes a label, and is announced as an image by that name.
class Components::Icon < Components::Base
  STYLES = %i[solid regular].freeze

  def initialize(name, style: :solid, label: nil, **attributes)
    raise ArgumentError, "unknown icon style #{style.inspect}" unless STYLES.include?(style)

    @name = name
    @style = style
    @label = label
    @attributes = attributes
  end

  def view_template
    i(class: [ "fa-#{@style}", @name, @attributes[:class] ], **accessibility, **@attributes.except(:class))
  end

  private

  def accessibility
    if @label
      { role: "img", aria: { label: @label }, title: @label }
    else
      { aria: { hidden: "true" } }
    end
  end
end
