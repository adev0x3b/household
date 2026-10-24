# frozen_string_literal: true

module Assistant
  class RecordGroceriesTool < ChangeTool
    description "Saves FOOD/COOKING items BOUGHT (pasta, eggs, flour, milk, oil, vegetables…), one item per ingredient, all in one call. " \
                "Each purchase ADDS to the amount on hand (a new ingredient is created) — use it whenever the user bought, " \
                "even if the ingredient already exists. For medical/health supplies use record_purchases. " \
                "Leave out anything the user did not say (quantity, price, how they paid): the result tells you what to ask."
    parameters(
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              ingredient: { type: "string", description: "What was bought" },
              quantity: { type: "number", description: "How much was bought — only if the user said it" },
              unit: { type: "string", description: "kg, g, l, ml, pcs… — only if the user said it" },
              amount: { type: "number", description: "What this item cost" },
              payment_method: PAYMENT
            },
            required: %w[ingredient]
          }
        },
        payment_method: PAYMENT.merge(description: "How everything was paid, when it's the same for all items"),
        date: DATE.merge(description: "When it was bought (default today). #{DATE[:description]}"),
        shop: { type: "string", description: "Where it was bought" },
        amount: { type: "number", description: "The price, when only one item was bought (several items: each has its own amount)" },
        confirm: CONFIRM
      },
      required: %w[items]
    )

    def execute(items: [], payment_method: nil, date: nil, shop: nil, amount: nil, total: nil, confirm: false)
      fail!("items is empty") if Array(items).empty?

      ops = priced_items(items, amount || total).map do |item|
        { op: "create", type: "ingredient_purchase",
          fields: { ingredient: item["ingredient"], quantity: item["quantity"], unit: item["unit"], amount: item["amount"],
                    payment_method: item["payment_method"].presence || payment_method, date: date, counterparty: shop } }
      end
      submit(ops, confirm: confirm)
    end
  end
end
