# frozen_string_literal: true

# Whether a grocery list is still being shopped, as a pill.
class Views::GroceryLists::StatusBadge < Views::Base
  LOOKS = {
    "active" => Components::StatusLook.new(tone: :neutral, icon: "fa-cart-shopping"),
    "completed" => Components::StatusLook.new(tone: :good)
  }.freeze

  def initialize(status:)
    @status = status.to_s
  end

  def view_template
    render LOOKS.fetch(@status).badge(label: t("grocery_lists.status.#{@status}"))
  end
end
