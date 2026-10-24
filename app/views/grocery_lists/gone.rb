# frozen_string_literal: true

# What a list's page becomes when someone else deletes the list while it is
# open (GroceryLists::Broadcaster.destroyed).
class Views::GroceryLists::Gone < Views::Base
  def view_template
    div(class: "grocery-list-show") do
      render Components::Notice.new(tone: :neutral) do
        p do
          plain t("grocery_lists.show.gone")
          plain " "
          a(href: grocery_lists_path) { t("grocery_lists.show.back") }
        end
      end
    end
  end
end
