# frozen_string_literal: true

module Assistant
  # Sharing waits for the user's button, because it shows the user's things
  # to someone else.
  class ShareTool < ChangeTool
    description "Shares a saved item (all its repeats), a therapy, a recipe, a grocery list or a book with another household " \
                "member, by name; undo: true stops sharing. ref is an id from search_records or the user's words. " \
                "Sharing waits for the user's button."
    parameters(
      type: "object",
      properties: {
        type: { type: "string", enum: %w[appointment medication task transaction lab_test_result meal collection recipe grocery_list book],
                description: "collection for a therapy" },
        ref: { type: "string" }, event_id: EVENT_ID,
        with: { type: "string", description: "The household member, by name" },
        undo: { type: "boolean", description: "Stop sharing instead" }
      },
      required: %w[type with]
    )

    def execute(with:, type: nil, ref: nil, event_id: nil, undo: false)
      ref = ref_or_event_id(ref, event_id)
      type ||= type_from_event_id(event_id)
      fail!("give type, or event_id") if type.blank?
      fail!("give ref, or event_id") if ref.blank?

      submit([ { op: undo ? "unshare" : "share", type: type, ref: ref.to_s, fields: { with: with } } ])
    end
  end
end
