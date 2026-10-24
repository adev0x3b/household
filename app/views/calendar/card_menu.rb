# frozen_string_literal: true

# The "more" menu of every card on a page of day cards: Delete this day
# (this dose of it, for a series taken several times a day) and, for a
# series that repeats, Delete the whole series, each asking first, worded
# "Ask Sam to…" when the owner must say yes. Drawn once for the page
# (Views::Calendar::DayMenus), since a copy on every card made up most of
# the calendar's weight, and filled by card_menu_controller.js for the card
# pressed.
class Views::Calendar::CardMenu < Views::Base
  ID = "card_menu"

  # What a card's button tells the menu: its day's address, whether its
  # series repeats, and, when the owner must say yes to a delete, the
  # owner's name.
  def self.opener_data(url:, repeats:, asking: nil)
    { action: "card-menu#open", card_menu_url_param: url, card_menu_repeats_param: repeats.to_s,
      card_menu_owner_param: asking }.compact
  end

  def view_template
    # Drawn at the page's end, far from the card pressed, so it names itself
    div(id: ID, class: "item-menu__menu item-menu__menu--floating", role: "group",
        aria: { label: t("links.cards.more") },
        data: { card_menu_target: "menu", action: "turbo:before-morph-element->card-menu#holdWhileOpen" }) do
      form(method: "post", data: { card_menu_target: "form", action: "submit->card-menu#chosen" }) do
        input(type: "hidden", name: "_method", value: "delete", autocomplete: "off")
        entry("occurrence", icon: "fa-trash")
        entry("series", icon: "fa-trash-can")
      end
    end
  end

  private

  # A delete of one scope. It carries both wordings, the viewer's own and
  # the "ask" one with the owner's name left for the controller to fill.
  def entry(scope, icon:)
    button(type: "submit", name: "scope", value: scope,
           class: "item-menu__entry item-menu__entry--danger",
           data: { card_menu_target: "entry", turbo_confirm: t("links.cards.delete_#{scope}_confirm"), **phrases(scope) }) do
      render Components::Icon.new(icon)
      span { t("links.cards.delete_#{scope}") }
    end
  end

  def phrases(scope)
    {
      label: t("links.cards.delete_#{scope}"),
      confirm: t("links.cards.delete_#{scope}_confirm"),
      ask_label: t("links.cards.ask_delete_#{scope}", name: "%{name}"),
      ask_confirm: t("links.cards.ask_delete_#{scope}_confirm", name: "%{name}")
    }
  end
end
