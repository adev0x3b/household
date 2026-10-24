# frozen_string_literal: true

# A dialog over the page: a header, a body that scrolls, and a footer that
# always shows, with Cancel and the modal's own action (Save, Share…). It is
# the browser's own modal dialog, so the page behind it can't be reached
# while it is open, and Escape closes it.
#
#   render Components::Modal.new(section: :files) do |modal|
#     modal.modal_header(title:, subtitle:, icon:)
#     modal.modal_form(url:, scope:) do |f|       # when the footer submits
#       modal.modal_body { fields }
#       modal.modal_footer { submit }
#     end
#   end
#
# Nothing else may come between the dialog and its body or footer: the
# dialog's height reaches the body through modal_form alone, and a long
# body would otherwise push the footer out of sight (the test suite checks
# every modal it renders: test/support/modal_structure.rb).
class Components::Modal < Components::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::TurboFrameTag

  SIZES = %i[small medium large].freeze

  # section: the part of the household the modal is about; its header icon
  # takes that color (see _sections.scss).
  # id: a stable id, for a modal a stream draws again in place
  # (turbo_stream.replace), as the share modal is after each share. Else
  # unique.
  def initialize(size: :medium, section: nil, id: nil)
    raise ArgumentError, "unknown modal size: #{size.inspect}" unless SIZES.include?(size)

    @dom_id = id || "modal_#{SecureRandom.hex(10)}"
    @size = size
    @title_id = "#{@dom_id}_title"
    @section = section
  end

  def view_template(&)
    turbo_frame_tag dom_id do
      dialog(
        class: "modal",
        aria: { labelledby: @title_id },
        tabindex: "-1",
        data: { controller: "modal", modal_toasts_value: Components::Toast::CONTAINER_ID,
                action: "click->modal#backdropClick close->modal#closed" }
      ) do
        div(class: "modal__backdrop")

        div(
          class: [ "modal__dialog modal__dialog--#{@size}", ("section--#{@section}" if @section) ],
          data: { modal_target: "dialog" },
          &
        )

        # While the modal is open nothing outside it can be pressed or read
        # aloud, so the toasts shown meanwhile are shown here instead, in a
        # polite live region like the page's own (Components::Toasts).
        div(class: "toast-container", aria: { live: "polite" }, data: { modal_target: "toasts" })
      end
    end
  end

  def modal_header(title:, subtitle: nil, icon: "fa-circle-info")
    render_close_button

    header(class: "modal__header") do
      div(class: "modal__header-content") do
        div(class: "modal__icon") do
          render Components::Icon.new(icon)
        end
        div(class: "modal__title-group") do
          h2(id: @title_id, class: "modal__title") { title }
          p(class: "modal__subtitle") { subtitle } if subtitle
        end
      end
    end
  end

  # The form around the body and the footer, for a modal whose footer
  # submits: form_with's options, the class added to its own. It leaves the
  # modal's frame, as Components::Form does, so an answer that redirects is
  # a visit of the page it names: left in the frame, Turbo would look for
  # the modal's frame in that page, find none, and only say that part of
  # the page couldn't be loaded.
  def modal_form(**options, &)
    form_with(**options.except(:class, :data), class: [ "modal__form", options[:class] ].compact.join(" "),
                                               data: { turbo_frame: "_top", **options.fetch(:data, {}) }, &)
  end

  def modal_body(&)
    div(class: "modal__body", &)
  end

  # dismiss: the closing button's words: Cancel, or Done where what the
  # modal does is already done when pressed (the share modal).
  def modal_footer(dismiss: t("modal.cancel"), &)
    footer(class: "modal__footer") do
      button(
        type: "button",
        class: "modal__btn modal__btn--cancel",
        data: { action: "click->modal#close" }
      ) { dismiss }
      yield if block_given?
    end
  end

  private

  attr_reader :dom_id

  def render_close_button
    button(
      type: "button",
      class: "modal__close",
      data: { action: "click->modal#close" },
      aria: { label: t("modal.close") }
    ) do
      render Components::Icon.new("fa-xmark")
    end
  end
end
