# frozen_string_literal: true

# The rest of an item's actions, behind one round "more" button: a menu of
# labelled entries, opened by dropdown_controller.js. A card or a row keeps
# at most two actions in sight (Components::ItemAction, the ones used
# most), and the rest go here, never in a row that wraps or spills. The top
# bar folds a page's actions the same way, with its own round button
# (`button_class:`). What deletes comes last, set apart, in whatever order
# the actions are given.
#
#   render Components::ItemMenu.new(label: t("books.card.more"), actions: [
#     Components::Action.new(href: edit_book_path(book), icon: "fa-pen", label: t("books.card.edit"), turbo_stream: true),
#     Components::Action.new(href: book_path(book), icon: "fa-trash", label: t("books.card.destroy"), method: :delete,
#                            confirm: t("books.confirm_destroy", title: book.title), danger: true)
#   ])
class Components::ItemMenu < Components::Base
  def initialize(label:, actions:, button_class: "item-action")
    @label = label
    @actions = actions
    @button_class = button_class
  end

  def view_template
    return if @actions.empty?

    div(class: "item-menu", data: { controller: "dropdown" }) do
      render Components::MenuButton.new(label: @label, button_class: @button_class,
                                        data: { action: "click->dropdown#toggle", dropdown_target: "toggler" })

      div(class: "item-menu__menu", data: { dropdown_target: "menu" }) do
        @actions.partition { !_1.danger }.flatten.each { |action| entry(action) }
      end
    end
  end

  private

  # Chosen, an entry folds the menu, so a question it asks first isn't
  # answered over a menu still open behind it.
  def entry(action)
    render Components::ActionControl.new(action, class: [ "item-menu__entry", ("item-menu__entry--danger" if action.danger) ],
                                                 data: { action: "click->dropdown#close" }) do
      render Components::Icon.new(action.icon)
      span { action.label }
    end
  end
end
