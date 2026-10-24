# frozen_string_literal: true

# A message that comes and goes. Its kind says what happened: :success for
# what is done, :notice for what has begun or is held, :alert for a refusal
# or a failure.
#
# A screen reader hears each toast as it is shown: an alert at once, as an
# alert, and the others when the reader pauses, through the polite region
# its container is (Components::Toasts). An alert stays until it is closed,
# since a refusal that goes by itself may go before it was read.
#
# The message and its optional second line are text, escaped like any other
# content: a toast often names someone else's thing (a housemate, an item on
# a shared list), and that must never become markup. A caller that needs a
# link passes an ActiveSupport::SafeBuffer built with a helper (link_to),
# which Phlex writes out as it is.
#
#   render Components::Toast.new(kind: :success, body: t("recipes.notices.created"))
class Components::Toast < Components::Base
  # The layout's one place for toasts, which answers and broadcasts add to.
  CONTAINER_ID = "toast-container"

  ICONS = {
    success: "fa-check-circle",
    notice: "fa-info-circle",
    alert: "fa-exclamation-circle"
  }.freeze

  # The flash carries other flags besides toasts (Devise's timedout), so
  # the layout asks before drawing one.
  def self.kind?(key) = ICONS.key?(key.to_sym)

  def initialize(kind:, body:, detail: nil)
    raise ArgumentError, "unknown toast kind: #{kind.inspect}" unless ICONS.key?(kind)

    @kind = kind
    @icon = ICONS.fetch(kind)
    @body = body
    @detail = detail
  end

  def view_template
    div(class: "toast toast--#{@kind}", role: ("alert" if alert?), data: toast_data) do
      div(class: "toast__body") do
        render Components::Icon.new(@icon, class: "toast__icon")
        span(class: "toast__message") { @body }
        button(
          type: "button",
          class: "toast__close",
          aria: { label: t("toast.close") },
          data: { action: "toast#close" }
        ) do
          render Components::Icon.new("fa-xmark")
        end
      end

      div(class: "toast__detail") { @detail } if @detail.present?

      # The time left, for the eye alone: a screen reader has already been
      # told the message, and needn't hear the bar count down.
      unless alert?
        progress(
          class: "toast__progress",
          max: "100",
          value: "100",
          aria: { hidden: "true" },
          data: { toast_target: "progress" }
        )
      end
    end
  end

  private

  def alert? = @kind == :alert

  # It waits while the pointer is over it or the focus is in it, so its
  # close button or its link can be reached before it goes.
  def toast_data
    {
      controller: "toast",
      toast_until_closed_value: alert?,
      action: "mouseenter->toast#pauseTimer mouseleave->toast#resumeTimer " \
              "focusin->toast#pauseTimer focusout->toast#resumeTimer"
    }
  end
end
