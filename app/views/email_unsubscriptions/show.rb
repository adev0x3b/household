# frozen_string_literal: true

# The page a reminder mail's link opens (EmailUnsubscriptionsController):
# the button that stops every reminder by email, or that none comes by
# email, or that the link no longer works. The sign-in page's card, since
# nobody need be signed in here.
class Views::EmailUnsubscriptions::Show < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  # token: the link's, sent back with the press. state: :emailed (a reminder
  # comes by email), :none, or :gone (the link no longer works).
  def initialize(token:, state:)
    @token = token
    @state = state
  end

  def page_title = t("email_unsubscriptions.show.title")

  def view_template
    div(class: "auth-hero") do
      div(class: "auth-card") do
        div(class: "auth-card__header") do
          h1(class: "auth-card__title") { t("email_unsubscriptions.show.title") }
          p(class: "auth-card__subtitle") { t("email_unsubscriptions.show.#{@state}") }
        end
        if @state == :emailed
          button_to(email_unsubscription_path, params: { token: @token }, class: "button is-primary is-fullwidth is-medium") do
            t("email_unsubscriptions.show.submit")
          end
        end
        div(class: "auth-card__links") { a(href: root_path, class: "auth-card__link") { t("email_unsubscriptions.show.to_household") } }
      end
    end
  end
end
