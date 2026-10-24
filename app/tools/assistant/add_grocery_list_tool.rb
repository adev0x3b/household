# frozen_string_literal: true

module Assistant
  # "Add tuna to the grocery list" is how people add to the list they have,
  # and models answer it with a new list named after the list or its items.
  # So unless the model confirms it wants another, the items go to a list in
  # use called that, or for such a name to the list in use (the resolver
  # asks which when several are).
  class AddGroceryListTool < ChangeTool
    description "Starts a NEW grocery list, when the user asks for one or has none in use (the context lists those in use). NOT for naming " \
                "dishes or meals to make (\"pasta for lunch\" is plan_meals). Its items if the user already named some (it's fine to start one " \
                "empty). To add items to a list in use, remove some, or check them off as bought, use update_record."
    parameters(
      type: "object",
      properties: {
        name: { type: "string" },
        items: {
          type: "array",
          items: {
            type: "object",
            properties: { ingredient: { type: "string" }, quantity: { type: "number", description: "Only if the user said it" },
                          unit: { type: "string", description: "Only if the user said it" } },
            required: %w[ingredient]
          }
        },
        confirm: CONFIRM
      },
      required: %w[name]
    )

    def execute(name: nil, items: [], confirm: false)
      meant = list_meant(name, items) unless confirm
      return submit([ { op: "create", type: "grocery_list", fields: { name: name, items: items_of(items) } } ], confirm: confirm) unless meant

      fail!("#{lists_in_use.pluck(:name).to_sentence} already in use: add items with update_record, or confirm: true starts another") if items.blank?
      submit([ { op: "update", type: "grocery_list", ref: (meant.id if meant.is_a?(GroceryList)), fields: { "items" => items_of(items) } } ])
    end

    private

    def lists_in_use = GroceryList.where(id: GroceryList.accessible_by(profile).select(:id)).active

    # The list in use called that, :in_use for a name that only names the
    # kind or one of the items, nil when it means a new one.
    def list_meant(name, items)
      return if name.blank? || !lists_in_use.exists?

      NameMatch.find(lists_in_use, name) || (:in_use if names_the_kind?(name) || names_an_item?(name, items))
    end

    def names_an_item?(name, items)
      said = TextMatch.fold(name).strip
      items_of(items).any? { |item| TextMatch.fold(item.is_a?(Hash) ? item["ingredient"].to_s : item).strip == said }
    end

    def names_the_kind?(name)
      list = Resources.fetch("grocery_list")
      (name.downcase.scan(/[[:alnum:]]{2,}/) - ChangeSets::Resolver::STOPWORDS).all? { list.kind_word?(_1) }
    end
  end
end
