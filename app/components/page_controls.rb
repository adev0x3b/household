# frozen_string_literal: true

# A page's controls in the top bar: an optional search (Components::IndexSearch)
# first, then the page's actions (Components::Action), one per thing done to
# the whole page. A page builds them in its view's `navbar_controls`
# (Views::Base):
#
#   Components::PageControls.new(
#     search: Components::IndexSearch.new(...),
#     actions: [ Components::Action.new(href: routes.new_recipe_path, icon: "fa-plus", label: t("recipes.index.new"), turbo_stream: true) ]
#   )
#
# The bar has two slots beside the bell, and the search takes one. The
# actions that fit them are round icon buttons, in the order given, so a
# page lists the ones used most first; the rest fold behind one "more"
# button (Components::ItemMenu), where an action that deletes always goes,
# set apart and last, however few the page has.
class Components::PageControls < Components::Base
  SLOTS = 2

  def initialize(search: nil, actions: [])
    @search = search
    @actions = actions
  end

  def view_template
    div(class: "page-controls") do
      render @search if @search
      visible.each { |action| control(action) }
      render Components::ItemMenu.new(label: t("page_controls.more"), actions: folded, button_class: "page-controls__action")
    end
  end

  private

  def slots = @search ? SLOTS - 1 : SLOTS

  def visible = @actions.reject(&:danger).first(slots)

  def folded = @actions - visible

  def control(action)
    render Components::ActionControl.new(action, class: [ "page-controls__action", ("is-active" if action.active) ],
                                                 aria: { label: action.label }, title: action.label) do
      render Components::Icon.new(action.icon)
    end
  end
end
