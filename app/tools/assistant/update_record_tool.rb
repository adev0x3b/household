# frozen_string_literal: true

module Assistant
  # A series' repeat changes only in what the user said: "Mondays and
  # Thursdays" keeps it weekly, and an end stops it after that day while the
  # past days stay.
  class UpdateRecordTool < ChangeTool
    # Search results and duplicate warnings show a series' repeat as
    # "repeats", and models echo that spelling back inside changes, so it is
    # read the same as "repeat".
    REPEAT_KEYS = %w[repeat repeats every days ends times].freeze

    description "Changes a saved record: new field values in changes (also a supply's low_stock_threshold, a purchase's " \
                "opened_on, an analyte's name); a lab report's values / remove_values; a grocery list's items / " \
                "remove_items / check_items / uncheck_items; a meal's recipes / remove_recipes (by name); how a series repeats; merge_into when two analytes are " \
                "the same test. ref: an id from search_records or the user's words (\"the lab report from last week\", " \
                "\"this week's grocery list\"); left out for a grocery list, it is the one in use."
    parameters(
      type: "object",
      properties: {
        type: { type: "string", enum: TYPES }, ref: { type: "string" }, event_id: EVENT_ID,
        changes: { type: "object", description: "Field → new value, only what changes (date, time, amount, title…)" },
        values: {
          type: "array", description: "Lab report only: values to fix or add",
          items: { type: "object", properties: { analyte: { type: "string" }, value: { type: "string" }, unit: { type: "string" } },
                   required: %w[analyte] }
        },
        remove_values: { type: "array", items: { type: "string" }, description: "Lab report only: analytes to drop" },
        items: {
          type: "array", description: "Grocery list only: items to add (quantity only if the user said it), or fix the quantity/unit of",
          items: { type: "object", properties: { ingredient: { type: "string" }, quantity: { type: "number" }, unit: { type: "string" } },
                   required: %w[ingredient] }
        },
        remove_items: { type: "array", items: { type: "string" }, description: "Grocery list only: ingredients to drop from the list" },
        check_items: { type: "array", items: { type: "string" }, description: "Grocery list only: ingredients to mark bought, by name" },
        uncheck_items: { type: "array", items: { type: "string" }, description: "Grocery list only: ingredients to mark not bought" },
        recipes: { type: "array", items: { type: "string" }, description: "Meal only: saved recipes to add to it, by name" },
        remove_recipes: { type: "array", items: { type: "string" }, description: "Meal only: recipes to take off it" },
        member: MEMBER.merge(description: "Payment only: the household member it's with, by name"),
        merge_into: { type: "string", description: "Analyte only: the analyte ref is the same test as; its values move there" },
        uses: USES.merge(description: "Medication only: EVERY supply each dose uses from now on (the medication itself, a syringe…) — replaces the old list"),
        **RECURRENCE, times: TIMES.merge(description: "Medication only: ALL the times of day a dose is taken from now on (HH:MM, or breakfast / lunch / dinner / bedtime) — replaces the old ones")
      },
      required: %w[type]
    )

    def execute(type: nil, ref: nil, event_id: nil, changes: {}, values: [], remove_values: [], items: [], remove_items: [],
                check_items: [], uncheck_items: [], recipes: [], remove_recipes: [], member: nil, repeat: nil, every: nil, days: nil, ends: nil, times: nil,
                merge_into: nil, uses: [])
      ref = ref_or_event_id(ref, event_id)
      changes = changes.to_h.stringify_keys
      merge_into ||= changes.delete("merge_into")
      # Lab values and repeat details sent inside changes count too.
      values = Array(values) + Array(changes.delete("values"))
      remove_values = Array(remove_values) + Array(changes.delete("remove_values"))
      items = Array(items) + Array(changes.delete("items"))
      remove_items = Array(remove_items) + Array(changes.delete("remove_items"))
      check_items = Array(check_items) + Array(changes.delete("check_items"))
      uncheck_items = Array(uncheck_items) + Array(changes.delete("uncheck_items"))
      recipes = Array(recipes) + Array(changes.delete("recipes"))
      remove_recipes = Array(remove_recipes) + Array(changes.delete("remove_recipes"))
      uses = Array.wrap(uses) + Array.wrap(changes.delete("uses")) + Array.wrap(changes.delete("supplies"))
      # Only a lab report takes values, and only a grocery list items, so they
      # say the type as surely as event_id does.
      type ||= type_from_event_id(event_id) || ("lab_test_result" if values.any? || remove_values.any?) ||
               ("grocery_list" if [ items, remove_items, check_items, uncheck_items ].any?(&:any?))
      fail!("give type, or event_id") if type.blank?
      # A grocery list may go unnamed: the one in use (ChangeSets::Resolver).
      fail!("give ref, or event_id") if ref.blank? && !Resources.lookup(type)&.in_use?
      # Merging replaces any other change: the merged analyte is gone after it.
      return submit([ { op: "merge", type: type, ref: ref.to_s, fields: { "into" => merge_into.to_s } } ]) if merge_into.present?

      if member.present?
        fail!("member is only for a payment (type transaction)") unless type == "transaction"
        changes["counterparty_profile_id"] = member_id(member)
      elsif type == "transaction" && (found = member_id_from_text(changes["counterparty"]))
        # A correction to who it was with ("that was actually paid by Marco")
        # given as plain counterparty text still links the household member.
        # counterparty_mode clears the existing text counterparty, because a
        # payment refuses both at once.
        changes["counterparty_profile_id"] = found
        changes["counterparty_mode"] = "profile"
        changes.delete("counterparty")
      end
      nested = changes.extract!(*REPEAT_KEYS)
      repeats = recurrence(repeat || nested["repeat"] || nested["repeats"], every || nested["every"], days || nested["days"],
                           ends || nested["ends"], times || nested["times"])
      submit([ { op: "update", type: type, ref: ref.to_s,
                 fields: changes.merge("values" => values, "remove_values" => remove_values, "recurrence" => repeats,
                                       "items" => items, "remove_items" => remove_items,
                                       "check_items" => check_items, "uncheck_items" => uncheck_items,
                                       "recipes" => recipes, "remove_recipes" => remove_recipes, "uses" => uses) } ])
    end
  end
end
