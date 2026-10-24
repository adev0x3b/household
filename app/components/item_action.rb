# frozen_string_literal: true

# One action on one item (a card, a list row, a line on the assistant's
# change set card), drawn as a small round icon button that names what it
# does in its tooltip and to a screen reader. It takes a
# Components::Action's keywords, since a round button is how most actions
# are drawn. A card keeps at most two in sight; the rest go behind
# Components::ItemMenu.
#
#   render Components::ItemAction.new(href: edit_recipe_path(recipe), icon: "fa-pen", label: t("recipes.card.edit"), turbo_stream: true)
#   render Components::ItemAction.new(icon: "fa-xmark", label: t("…"), data: { action: "nested-fields#remove" })
#
# `id:` is for a button whose answer draws its row again, so the focus
# finds it there (focus_keeper.js).
class Components::ItemAction < Components::Base
  def initialize(id: nil, **action)
    @id = id
    @action = Components::Action.new(**action)
  end

  def view_template
    render Components::ActionControl.new(@action, id: @id, class: [ "item-action", ("item-action--danger" if @action.danger) ],
                                                  aria: { label: @action.label }, title: @action.label) do
      render Components::Icon.new(@action.icon)
    end
  end
end
