# frozen_string_literal: true

module Assistant
  class AddRecipeTool < ChangeTool
    description "Saves a new recipe: its steps in order and the ingredients it needs, all in one call. To add or " \
                "remove an ingredient or step on a saved recipe, use update_record instead."
    parameters(
      type: "object",
      properties: {
        name: { type: "string" },
        description: { type: "string" },
        steps: {
          type: "array", description: "In the order they're done",
          items: { type: "object", properties: { instruction: { type: "string" } }, required: %w[instruction] }
        },
        ingredients: {
          type: "array",
          items: {
            type: "object",
            properties: { ingredient: { type: "string" }, quantity: { type: "number" },
                          unit: { type: "string", description: "Only if the user said it" } },
            required: %w[ingredient quantity]
          }
        },
        confirm: CONFIRM
      },
      required: %w[name]
    )

    def execute(name: nil, description: nil, steps: [], ingredients: [], confirm: false)
      fields = {
        name: name, description: description,
        steps: items_of(steps),
        ingredients: items_of(ingredients)
      }
      submit([ { op: "create", type: "recipe", fields: fields } ], confirm: confirm)
    end
  end
end
