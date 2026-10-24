# frozen_string_literal: true

module Assistant
  class RecordPurchasesTool < ChangeTool
    description "Saves MEDICAL/HEALTH SUPPLIES bought (vials, needles, syringes, bandages, test strips, medications for therapies), " \
                "one item per supply, all in one call. For food items like pasta, eggs, oil, use record_groceries instead. " \
                "Leave out anything the user did not say (quantity, price, how they paid): the result tells you what to ask."
    parameters(
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              supply: { type: "string", description: "What was bought" },
              quantity: { type: "number", description: "Only if the user said it" },
              unit: { type: "string", description: "What the quantity counts (ml, mg, pcs…), only if the user said it" },
              amount: { type: "number", description: "What this item cost" },
              payment_method: PAYMENT,
              expires_on: DATE.merge(description: "Expiry date on the pack, if the user said it. #{DATE[:description]}"),
              opened_on: DATE.merge(description: "When it was opened, if the user said it. #{DATE[:description]}")
            },
            required: %w[supply]
          }
        },
        payment_method: PAYMENT.merge(description: "How everything was paid, when it's the same for all items"),
        date: DATE.merge(description: "When it was bought (default today). #{DATE[:description]}"),
        shop: { type: "string", description: "Where it was bought" },
        amount: { type: "number", description: "The price, when only one item was bought (several items: each has its own amount)" },
        therapy: THERAPY, confirm: CONFIRM
      },
      required: %w[items]
    )

    def execute(items: [], payment_method: nil, date: nil, shop: nil, therapy: nil, amount: nil, total: nil, confirm: false)
      fail!("items is empty") if Array(items).empty?

      ops = priced_items(items, amount || total).map do |item|
        { op: "create", type: "supply_purchase",
          fields: { supply: item["supply"], quantity: item["quantity"], supply_unit: item["unit"], amount: item["amount"],
                    payment_method: item["payment_method"].presence || payment_method,
                    date: date, counterparty: shop, therapy: therapy,
                    expires_on: item["expires_on"], opened_on: item["opened_on"] } }
      end
      submit(ops, confirm: confirm)
    end
  end
end
