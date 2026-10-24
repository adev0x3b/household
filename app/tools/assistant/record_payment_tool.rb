# frozen_string_literal: true

module Assistant
  # A payment with a household member is linked to their profile, so they
  # read it from their side and it settles what is owed between the two.
  class RecordPaymentTool < ChangeTool
    description "Saves an expense or income (a bill, rent, salary…), including money with a household member (member). " \
                "Supplies bought go to record_purchases and a visit's fee to book_appointment instead."
    parameters(
      type: "object",
      properties: {
        title: { type: "string" },
        amount: { type: "number", description: "How much, without a sign: kind says which way it went" },
        kind: { type: "string", enum: Transaction::Details.kinds.keys,
                description: "income when money came to the user (\"Marco paid me\", a salary), expense when the user paid" },
        category: { type: "string", enum: Transaction::Details.categories.keys },
        payment_method: PAYMENT, date: DATE,
        member: MEMBER,
        counterparty: { type: "string", description: "Anyone else who was paid, or who paid" },
        notes: { type: "string" }, **RECURRENCE,
        confirm: CONFIRM
      }
    )

    # Models add a type by analogy with the tools that take several, so it
    # is accepted and ignored. They still send the notes as description.
    def execute(title: nil, amount: nil, kind: nil, category: nil, payment_method: nil, date: nil, member: nil, counterparty: nil,
                notes: nil, description: nil, repeat: nil, every: nil, days: nil, ends: nil, confirm: false, type: nil)
      # A household member named as the counterparty instead of the member
      # still gets to see the payment, so the name is looked up the same way.
      member_id = member.present? ? member_id(member) : member_id_from_text(counterparty)
      counterparty = nil if member_id
      submit([ { op: "create", type: "transaction",
                 fields: { title: title, amount: amount, kind: kind, category: category, payment_method: payment_method,
                           date: date, counterparty_profile_id: member_id, counterparty: counterparty,
                           notes: notes.presence || description, recurrence: recurrence(repeat, every, days, ends) } } ], confirm: confirm)
    end
  end
end
