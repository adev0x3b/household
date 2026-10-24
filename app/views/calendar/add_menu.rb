# frozen_string_literal: true

# The menu every day's "+" opens on a page of day cards: each kind of
# series (Event.types), in the colour of the section a new one starts in,
# opening that kind's form for the day pressed. Drawn once for the page
# (Views::Calendar::DayMenus) rather than once a day, and given the day by
# day_add_controller.js, as the form's one field.
class Views::Calendar::AddMenu < Views::Base
  ID = "day_add_menu"

  # What a day's "+" tells the menu: the day.
  def self.opener_data(date) = { action: "day-add#open", day_add_date_param: date.iso8601 }

  def view_template
    # Drawn at the page's end, far from the day pressed, so it names itself
    div(id: ID, class: "day-add-menu", role: "group", aria: { label: t("calendar.day_card.add_event") },
        data: { day_add_target: "menu", action: "turbo:before-morph-element->day-add#holdWhileOpen" }) do
      form(method: "get", data: { turbo_stream: true, action: "submit->day-add#chosen" }) do
        input(type: "hidden", name: "date", autocomplete: "off", data: { day_add_target: "date" })
        Event.types.each { |type| option(type) }
      end
    end
  end

  private

  def option(type)
    button(type: "submit", formaction: new_polymorphic_path(type),
           class: "day-add-menu__option section--#{type.starting_section}") do
      render Components::Icon.new(Views::Calendar::Cards.for(type).icon)
      span { t("calendar.day_card.event_types.#{type.route_key}") }
    end
  end
end
