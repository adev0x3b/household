# frozen_string_literal: true

# The "more" menu of every card on a page of day cards: the day's status
# (skip it, cancel it, or set it back to pending), then Delete this day
# (this dose of it, for a series taken several times a day) and, for a
# series that repeats, Delete the whole series, each delete asking first.
# A press is worded "Ask Sam to…" when the owner must say yes. Drawn once
# for the page (Views::Calendar::DayMenus), since a copy on every card made
# up most of the calendar's weight, and filled by card_menu_controller.js
# for the card pressed.
class Views::Calendar::CardMenu < Views::Base
  ID = "card_menu"
  STATUS_ICONS = { "skipped" => "fa-forward", "cancelled" => "fa-xmark", "pending" => "fa-rotate-left" }.freeze

  # What a card's button tells the menu, for each part the viewer may use:
  # the day's status address and the statuses offered for it, its own
  # address for the deletes and whether its series repeats, and, for a
  # part whose presses wait for the owner's OK, the owner's name.
  def self.opener_data(repeats:, delete_url: nil, delete_asking: nil, status_url: nil, statuses: [], status_asking: nil)
    {
      action: "card-menu#open", card_menu_repeats_param: repeats.to_s,
      card_menu_delete_url_param: delete_url, card_menu_delete_owner_param: delete_asking,
      card_menu_status_url_param: status_url, card_menu_statuses_param: (statuses.to_json if status_url),
      card_menu_status_owner_param: status_asking
    }.compact
  end

  def view_template
    # Drawn at the page's end, far from the card pressed, so it names itself
    div(id: ID, class: "item-menu__menu item-menu__menu--floating", role: "group",
        aria: { label: t("links.cards.more") },
        data: { card_menu_target: "menu", action: "turbo:before-morph-element->card-menu#holdWhileOpen" }) do
      press_form("patch", target: "statusForm") { STATUS_ICONS.each { |status, icon| status_entry(status, icon:) } }
      press_form("delete", target: "deleteForm") do
        delete_entry("occurrence", icon: "fa-trash")
        delete_entry("series", icon: "fa-trash-can")
      end
    end
  end

  private

  def press_form(method, target:, &)
    form(method: "post", data: { card_menu_target: target, action: "submit->card-menu#chosen" }) do
      input(type: "hidden", name: "_method", value: method, autocomplete: "off")
      yield
    end
  end

  # A status the day can be given; it changes nothing that can't be put
  # back, so it asks nothing first.
  def status_entry(status, icon:)
    button(type: "submit", name: "status", value: status, class: "item-menu__entry",
           data: { card_menu_target: "entry", label: t("links.cards.status.#{status}"),
                   ask_label: t("links.cards.ask_status.#{status}", name: "%{name}") }) do
      render Components::Icon.new(icon)
      span { t("links.cards.status.#{status}") }
    end
  end

  # A delete of one scope. It carries both wordings, the viewer's own and
  # the "ask" one with the owner's name left for the controller to fill.
  def delete_entry(scope, icon:)
    button(type: "submit", name: "scope", value: scope,
           class: "item-menu__entry item-menu__entry--danger",
           data: { card_menu_target: "entry", turbo_confirm: t("links.cards.delete_#{scope}_confirm"), **delete_phrases(scope) }) do
      render Components::Icon.new(icon)
      span { t("links.cards.delete_#{scope}") }
    end
  end

  def delete_phrases(scope)
    {
      label: t("links.cards.delete_#{scope}"),
      confirm: t("links.cards.delete_#{scope}_confirm"),
      ask_label: t("links.cards.ask_delete_#{scope}", name: "%{name}"),
      ask_confirm: t("links.cards.ask_delete_#{scope}_confirm", name: "%{name}")
    }
  end
end
