# frozen_string_literal: true

module Assistant
  class AddTaskTool < ChangeTool
    description "Saves a to-do, once or repeating."
    parameters(
      type: "object",
      properties: {
        title: { type: "string" }, date: DATE, notes: { type: "string" },
        priority: { type: "string", enum: Task::Details.priorities.keys },
        **RECURRENCE,
        therapy: THERAPY, confirm: CONFIRM
      },
      required: %w[title]
    )

    # Models still send the notes as description.
    def execute(title: nil, date: nil, notes: nil, description: nil, priority: nil, repeat: nil, every: nil, days: nil, ends: nil,
                therapy: nil, confirm: false)
      submit([ { op: "create", type: "task",
                 fields: { title: title, date: date, notes: notes.presence || description, priority: priority, therapy: therapy,
                           recurrence: recurrence(repeat, every, days, ends) } } ], confirm: confirm)
    end
  end
end
