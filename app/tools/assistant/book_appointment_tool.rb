# frozen_string_literal: true

module Assistant
  # A fee for a visit still ahead stays unpaid until the visit is marked
  # done.
  class BookAppointmentTool < ChangeTool
    description "Saves an appointment (a visit booked or already done — medical by default; kind for work, social or personal " \
                "ones) and its fee. Pass only what the user said. To mark an existing appointment as done use mark_done, not this."
    parameters(
      type: "object",
      properties: {
        counterpart: { type: "string", description: "Who it is with: the doctor or clinic, or the person or company" },
        kind: { type: "string", enum: Appointment::Kind::ALL, description: "Default medical" },
        date: DATE, time: { type: "string", description: "HH:MM — only if the user said it" },
        title: { type: "string" }, location: { type: "string" }, notes: { type: "string" },
        amount: { type: "number", description: "The fee" }, payment_method: PAYMENT,
        **RECURRENCE, therapy: THERAPY, confirm: CONFIRM
      }
    )

    # Models add a type by analogy with the tools that take several, so it
    # is accepted and ignored. They still call the counterpart provider.
    def execute(counterpart: nil, provider: nil, kind: nil, date: nil, time: nil, title: nil, location: nil, notes: nil, amount: nil,
                payment_method: nil, repeat: nil, every: nil, days: nil, ends: nil, therapy: nil, confirm: false, type: nil)
      submit([ { op: "create", type: "appointment",
                 fields: { counterpart: counterpart.presence || provider, kind: kind, date: date, time: time, title: title,
                           location: location, notes: notes, amount: amount, payment_method: payment_method, therapy: therapy,
                           recurrence: recurrence(repeat, every, days, ends) } } ], confirm: confirm)
    end
  end
end
