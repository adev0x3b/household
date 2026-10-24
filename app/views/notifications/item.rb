# frozen_string_literal: true

# One notification: who did what, to what, how long ago. The row itself is
# the action: it marks the notification read and opens what it's about.
# One that asks for an answer (Notifications::Destination#actions: a link
# to accept, a change to approve) carries its buttons under it while the
# question is open. They are forms beside the row's, since a form can't
# hold another.
class Views::Notifications::Item < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  def self.dom_id(notification) = "notification_#{notification.id}"
  def self.button_id(notification) = "#{dom_id(notification)}_open"

  def initialize(notification:)
    @notification = notification
  end

  def view_template
    div(id: self.class.dom_id(@notification), class: "notifications__row") do
      # No token of its own: the row is also rendered outside a request (the
      # live broadcast), and Turbo sends the page's token with the form.
      button_to(
        notification_read_receipt_path(@notification),
        id: self.class.button_id(@notification),
        authenticity_token: false,
        class: "notifications__item#{" is-unread" if @notification.unread?}",
        form_class: "notifications__item-form",
      ) do
        span(class: "notifications__dot", aria: { hidden: "true" })
        span(class: "notifications__text") do
          span(class: "notifications__item-title") { wording.title }
          if (detail = wording.detail).present?
            span(class: "notifications__item-subject") { detail }
          end
          span(class: "notifications__item-time") do
            time_ago(@notification.created_at)
          end
        end
      end
      answers if destination.actions.any?
    end
  end

  private

  def wording = ::Notifications::Wording.new(@notification)
  def destination = @destination ||= ::Notifications::Destination.new(@notification)

  def answers
    div(class: "notifications__actions") do
      destination.actions.each do |action|
        button_to(t("notifications.actions.#{action.name}"), action.path, method: action.verb, authenticity_token: false,
                                                                          class: "notifications__action notifications__action--#{action.name}",
                                                                          form_class: "notifications__action-form", form: { data: { turbo_stream: true } })
      end
    end
  end
end
