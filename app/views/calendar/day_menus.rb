# frozen_string_literal: true

# Around the day cards of a page (the calendar's month, home's today): the
# menus their buttons open, a card's "more" and a day's "+", drawn once
# after them. A card a live push redraws keeps working, since its buttons
# only name the day they are about.
#
#   render Views::Calendar::DayMenus.new { render Views::Calendar::DayCard.new(…) }
class Views::Calendar::DayMenus < Views::Base
  def view_template(&)
    div(data: { controller: "card-menu day-add" }) do
      yield
      render Views::Calendar::CardMenu.new
      render Views::Calendar::AddMenu.new
    end
  end
end
