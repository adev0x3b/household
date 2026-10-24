# frozen_string_literal: true

module Assistant
  # What people and models say, made the app's own values: an enum's words,
  # a way of paying, a spending category or a kind of meal said another way
  # ("bonifico", "restaurant"), and an amount written any way.
  #
  #   Normalize.payment("Credit card")   # => "card"
  #   Normalize.amount("1.250,50")       # => "1250.50"
  module Normalize
    # What people call a way of paying, as Transaction::Details.payment_methods names it.
    PAYMENT_ALIASES = { "credit_card" => "card", "debit_card" => "card", "bancomat" => "card", "carta" => "card",
                        "carta_di_credito" => "card", "pos" => "card", "contanti" => "cash", "contante" => "cash",
                        "bonifico" => "bank_transfer", "transfer" => "bank_transfer", "wire" => "bank_transfer" }.freeze

    # What people call a spending category, as Transaction::Details.categories names it.
    CATEGORY_ALIASES = { "rent" => "housing", "affitto" => "housing", "mortgage" => "housing", "mutuo" => "housing",
                         "casa" => "housing", "home" => "housing", "bills" => "utilities", "bollette" => "utilities",
                         "food" => "groceries", "spesa" => "groceries", "supermarket" => "groceries",
                         "health" => "healthcare", "medical" => "healthcare", "salute" => "healthcare",
                         "stipendio" => "salary", "paycheck" => "salary", "wage" => "salary", "tasse" => "taxes",
                         "tax" => "taxes", "loan" => "debt", "transport" => "transportation", "other" => "miscellaneous",
                         "altro" => "miscellaneous", "restaurant" => "dining_out", "restaurants" => "dining_out",
                         "ristorante" => "dining_out", "ristoranti" => "dining_out", "takeaway" => "dining_out",
                         "takeout" => "dining_out", "delivery" => "dining_out", "eating_out" => "dining_out",
                         "dining" => "dining_out" }.freeze

    # What people call a kind of meal or a part of the day, as
    # Meal::Details.kinds and Meal::Details.meal_types name them.
    MEAL_KIND_ALIASES = { "restaurant" => "eating_out", "ristorante" => "eating_out", "out" => "eating_out", "dining_out" => "eating_out",
                          "eat_out" => "eating_out", "takeaway" => "ordered_in", "takeout" => "ordered_in", "take_away" => "ordered_in",
                          "delivery" => "ordered_in", "delivered" => "ordered_in", "ordered" => "ordered_in", "order_in" => "ordered_in",
                          "cooked" => "home", "at_home" => "home", "cook" => "home", "recipe" => "home" }.freeze
    MEAL_TYPE_ALIASES = { "supper" => "dinner", "cena" => "dinner", "evening" => "dinner", "pranzo" => "lunch", "midday" => "lunch",
                          "colazione" => "breakfast", "morning" => "breakfast", "spuntino" => "snack", "merenda" => "snack" }.freeze

    module_function

    # Models capitalize, so "Bank transfer" is read as "bank_transfer".
    def enum(value) = value.is_a?(String) ? value.strip.downcase.tr(" -", "__") : value

    def payment(value) = enum(value).then { PAYMENT_ALIASES.fetch(_1, _1) }
    def category(value) = enum(value).then { CATEGORY_ALIASES.fetch(_1, _1) }
    def meal_kind(value) = enum(value).then { MEAL_KIND_ALIASES.fetch(_1, _1) }
    def meal_type(value) = enum(value).then { MEAL_TYPE_ALIASES.fetch(_1, _1) }

    # "50", "50,00", "€ 1.250,50" or "32 euros" as a plain decimal string.
    def amount(value)
      return if value.blank?

      number = value.to_s[/[+-]?\d[\d.,]*/]
      return value.to_s unless number

      if number.count(",") == 1 && number.count(".").positive? && number.rindex(",") > number.rindex(".")
        number.delete(".").tr(",", ".")             # 1.250,50
      elsif number.count(",") == 1 && !number.include?(".") && number.split(",").last.length != 3
        number.tr(",", ".")                         # 50,5 / 12,50
      else
        number.delete(",")                          # 1,250.50 / 1,250
      end
    end
  end
end
