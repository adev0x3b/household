# frozen_string_literal: true

# How far a list's shop has got: "3 of 5 bought" for wherever the list puts
# it, and a bar once there is something on it to buy.
class Views::GroceryLists::Progress < Views::Base
  def initialize(grocery_list:)
    @checked = grocery_list.checked_count
    @total = grocery_list.total_count
  end

  def text
    return t("grocery_lists.progress.empty") if @total.zero?

    t("grocery_lists.progress.bought", checked: @checked, total: @total)
  end

  def view_template
    render Components::ProgressBar.new(value: @checked, max: @total, label: text) if @total.positive?
  end
end
