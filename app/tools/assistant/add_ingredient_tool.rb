# frozen_string_literal: true

module Assistant
  class AddIngredientTool < ChangeTool
    description "Saves a new FOOD ITEM in the pantry catalog (pasta, eggs, oil, flour, spices, vegetables, canned goods, cheese, etc.), " \
                "with how much is on hand and its unit — no purchase involved. If the user BOUGHT it, use record_groceries (it adds to the stock). " \
                "For medical/health supplies, use record_purchases. To correct an existing ingredient's amount or unit, use update_record " \
                "(that REPLACES the amount, it doesn't add)."
    parameters(
      type: "object",
      properties: {
        name: { type: "string" },
        quantity: { type: "number", description: "How much is on hand — default 0" },
        unit: { type: "string", description: "e.g. kg, l, pcs — only if the user said it" },
        confirm: CONFIRM
      },
      required: %w[name]
    )

    def execute(name: nil, quantity: nil, unit: nil, confirm: false)
      submit([ { op: "create", type: "ingredient", fields: { name: name, quantity: quantity, unit_name: unit } } ], confirm: confirm)
    end
  end
end
