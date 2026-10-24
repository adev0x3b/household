# frozen_string_literal: true

# The layout's one place for toasts: the flash's, from the request before,
# and those failed_request_controller.js shows when a request of Turbo's
# gets no answer the app could word, whose words it keeps ready here.
class Components::Toasts < Components::Base
  def initialize(flash:)
    @flash = flash
  end

  def view_template
    # Kept through a catch-up refresh, which would otherwise take a toast
    # away before it is read. A polite live region, so that a toast added to
    # it is read when the screen reader pauses; an alert toast is its own
    # region, and is read at once.
    div(id: Components::Toast::CONTAINER_ID, class: "toast-container", aria: { live: "polite" },
        data: container_data) do
      flash_toasts
      failure_toast("offline", t("failures.offline"))
      failure_toast("serverError", t("failures.server_error"))
      failure_toast("missing", t("failures.missing"))
    end
  end

  private

  def container_data
    {
      controller: "failed-request",
      catch_up_target: "kept",
      action: "turbo:fetch-request-error@document->failed-request#unanswered " \
              "turbo:before-fetch-response@document->failed-request#answered " \
              "turbo:frame-missing@document->failed-request#frameMissing"
    }
  end

  # Only the toasts' own kinds: Devise keeps other flags in the flash
  # (timedout), and a flag's value isn't a message.
  def flash_toasts
    @flash.each do |kind, message|
      next unless Components::Toast.kind?(kind) && message.is_a?(String)

      render Components::Toast.new(kind: kind.to_sym, body: message)
    end
  end

  def failure_toast(target, message)
    template(data: { failed_request_target: target }) { render Components::Toast.new(kind: :alert, body: message) }
  end
end
