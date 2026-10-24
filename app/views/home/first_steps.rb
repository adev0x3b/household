# frozen_string_literal: true

# What the overview shows a household with nothing on any calendar yet: a
# word of welcome, where everything begins, and the way there. Empty
# figures and dashes would only say that nothing has happened.
class Views::Home::FirstSteps < Views::Base
  def view_template
    section(class: "home-first-steps", aria: { labelledby: "home-first-steps-title" }) do
      render Components::Icon.new("fa-seedling", class: "home-first-steps__icon")
      h2(id: "home-first-steps-title", class: "home-first-steps__title") { t("home.overview.first_steps.title") }
      p(class: "home-first-steps__body") { t("home.overview.first_steps.body") }
      div(class: "home-first-steps__actions") do
        a(href: calendar_path, class: "button is-primary") do
          render Components::Icon.new("fa-calendar-days")
          span { t("home.overview.first_steps.calendar") }
        end
        a(href: household_path, class: "home-first-steps__link") { t("home.overview.first_steps.household") }
      end
    end
  end
end
