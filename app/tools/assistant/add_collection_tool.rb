# frozen_string_literal: true

module Assistant
  # Every write tool puts a record in a collection by naming it, which
  # creates the collection when it doesn't exist, so this tool is only for a
  # collection on its own.
  class AddCollectionTool < ChangeTool
    description "Saves a new therapy (a treatment that groups doses, supplies and visits), or any named group of items " \
                "(section says where it belongs; default healthcare)."
    parameters(
      type: "object",
      properties: {
        name: { type: "string" }, notes: { type: "string" },
        section: { type: "string", enum: Collection::SECTIONS, description: "Default healthcare (a therapy)" },
        confirm: CONFIRM
      },
      required: %w[name]
    )

    # Models still send the notes as description.
    def execute(name: nil, notes: nil, section: nil, description: nil, confirm: false)
      submit([ { op: "create", type: "collection",
                 fields: { name: name, notes: notes.presence || description, section: section.presence || "healthcare" } } ], confirm: confirm)
    end
  end
end
