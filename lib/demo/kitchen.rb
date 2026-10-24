# frozen_string_literal: true

module Demo
  # Pantry and meals. Alex keeps the pantry and the recipes (shared with the
  # others) and plans the week every Friday: dinners at home from the recipe
  # book, a takeaway or a dinner out, pancakes on Sunday. The shopping list
  # is whatever next week's recipes need that isn't on the shelf, bought on
  # Saturday; each meal eaten takes its ingredients off the shelf. So the
  # pantry today is what six months of cooking and shopping left in it.
  #
  # The days ahead are planned too, with one dinner the pantry can't cover
  # yet and a shopping list half done.
  class Kitchen < Part
    SHOPS = [ "Coop Saragozza", "Esselunga", "Mercato delle Erbe" ].freeze

    # name => [ unit, pack size, pack price, on the shelf at the start ]
    PANTRY = {
      "Spaghetti" => [ "g", 500, 1.15, 500 ], "Rice" => [ "g", 1000, 2.4, 600 ], "Arborio rice" => [ "g", 1000, 3.3, 0 ],
      "Flour" => [ "g", 1000, 0.95, 800 ], "Rolled oats" => [ "g", 500, 1.6, 300 ], "Red lentils" => [ "g", 500, 1.9, 0 ],
      "Canned tomatoes" => [ "g", 400, 0.85, 800 ], "Olive oil" => [ "ml", 1000, 8.9, 400 ], "Milk" => [ "ml", 1000, 1.35, 500 ],
      "Eggs" => [ "pcs", 6, 2.1, 4 ], "Butter" => [ "g", 250, 2.6, 120 ], "Parmesan" => [ "g", 200, 4.5, 80 ],
      "Mozzarella" => [ "g", 250, 2.2, 0 ], "Chicken breast" => [ "g", 500, 5.9, 0 ], "Minced beef" => [ "g", 400, 4.8, 0 ],
      "Onions" => [ "pcs", 5, 1.5, 3 ], "Garlic" => [ "pcs", 10, 0.9, 6 ], "Carrots" => [ "pcs", 6, 1.2, 2 ],
      "Potatoes" => [ "g", 1500, 2.1, 0 ], "Bell peppers" => [ "pcs", 3, 2.4, 0 ], "Zucchini" => [ "pcs", 3, 1.8, 0 ],
      "Mushrooms" => [ "g", 250, 1.9, 0 ], "Tomatoes" => [ "g", 500, 1.8, 0 ], "Cucumber" => [ "pcs", 1, 0.8, 0 ],
      "Feta" => [ "g", 200, 2.3, 0 ], "Bananas" => [ "pcs", 6, 1.6, 2 ], "Yogurt" => [ "g", 500, 1.7, 0 ],
      "Coconut milk" => [ "ml", 400, 1.8, 400 ], "Curry paste" => [ "g", 100, 2.2, 0 ], "Soy sauce" => [ "ml", 250, 2.1, 150 ],
      "Tortillas" => [ "pcs", 8, 1.9, 0 ], "Black beans" => [ "g", 400, 0.95, 400 ], "Honey" => [ "g", 250, 3.9, 200 ],
      "Sugar" => [ "g", 1000, 1.1, 700 ], "Coffee" => [ "g", 250, 4.2, 100 ], "Salmon fillets" => [ "g", 400, 9.8, 0 ],
      "Asparagus" => [ "g", 500, 3.6, 0 ]
    }.freeze

    # Where each is found in the shop; whatever isn't listed is a dry good.
    CATEGORY_OF = {
      "produce" => [ "Onions", "Garlic", "Carrots", "Potatoes", "Bell peppers", "Zucchini", "Mushrooms", "Tomatoes", "Cucumber", "Bananas", "Asparagus" ],
      "dairy_eggs" => [ "Milk", "Eggs", "Butter", "Parmesan", "Mozzarella", "Feta", "Yogurt" ],
      "meat_fish" => [ "Chicken breast", "Minced beef", "Salmon fillets" ],
      "bakery" => [ "Tortillas" ],
      "drinks" => [ "Coffee" ]
    }.flat_map { |category, names| names.map { |name| [ name, category ] } }.to_h.freeze

    # name => [ description, [ [ ingredient, quantity, unit ], … ], steps ]
    RECIPES = {
      "Spaghetti al pomodoro" => [ "The weeknight default.", [ [ "Spaghetti", 320, "g" ], [ "Canned tomatoes", 400, "g" ], [ "Garlic", 2, "pcs" ], [ "Olive oil", 30, "ml" ], [ "Parmesan", 40, "g" ] ],
                                   [ "Warm the oil with the garlic, add the tomatoes and simmer 15 minutes.", "Cook the spaghetti one minute short of the packet time.", "Finish the pasta in the sauce with a ladle of its water. Parmesan at the table." ] ],
      "Chicken curry" => [ "Mild enough for everyone.", [ [ "Chicken breast", 500, "g" ], [ "Coconut milk", 400, "ml" ], [ "Curry paste", 50, "g" ], [ "Onions", 1, "pcs" ], [ "Rice", 300, "g" ] ],
                           [ "Soften the onion, fry the curry paste one minute.", "Add the chicken in pieces, brown it, pour in the coconut milk.", "Simmer 20 minutes while the rice cooks." ] ],
      "Veggie stir-fry" => [ "Whatever vegetables are left, over rice.", [ [ "Bell peppers", 2, "pcs" ], [ "Zucchini", 2, "pcs" ], [ "Carrots", 2, "pcs" ], [ "Mushrooms", 250, "g" ], [ "Soy sauce", 40, "ml" ], [ "Rice", 300, "g" ] ],
                             [ "Start the rice.", "Cut everything into strips and fry on high heat, carrots first.", "Soy sauce at the end, off the heat." ] ],
      "Mushroom risotto" => [ nil, [ [ "Arborio rice", 320, "g" ], [ "Mushrooms", 250, "g" ], [ "Onions", 1, "pcs" ], [ "Butter", 40, "g" ], [ "Parmesan", 60, "g" ] ],
                              [ "Brown the mushrooms and set them aside.", "Toast the rice with the onion, then add hot stock a ladle at a time for 16 minutes.", "Stir in the mushrooms, butter and parmesan. Rest two minutes." ] ],
      "Red lentil soup" => [ "Better the day after.", [ [ "Red lentils", 250, "g" ], [ "Carrots", 2, "pcs" ], [ "Onions", 1, "pcs" ], [ "Canned tomatoes", 400, "g" ], [ "Olive oil", 20, "ml" ] ],
                             [ "Soften the onion and carrots in the oil.", "Add lentils, tomatoes and a litre of water. Simmer 25 minutes.", "Blend half of it and stir back in." ] ],
      "Margherita pizza" => [ "Dough in the morning, pizza at night.", [ [ "Flour", 500, "g" ], [ "Canned tomatoes", 400, "g" ], [ "Mozzarella", 250, "g" ], [ "Olive oil", 20, "ml" ] ],
                              [ "Knead flour, water, yeast and salt. Let it rise 8 hours.", "Stretch into two trays, spread the tomato.", "Bake at 250° for 10 minutes, mozzarella on for the last 4." ] ],
      "Beef tacos" => [ nil, [ [ "Tortillas", 8, "pcs" ], [ "Minced beef", 400, "g" ], [ "Black beans", 400, "g" ], [ "Tomatoes", 200, "g" ], [ "Onions", 1, "pcs" ] ],
                        [ "Brown the beef with the onion, add the beans.", "Dice the tomatoes.", "Warm the tortillas and let everyone fill their own." ] ],
      "Greek salad" => [ "No cooking.", [ [ "Tomatoes", 400, "g" ], [ "Cucumber", 1, "pcs" ], [ "Feta", 200, "g" ], [ "Onions", 1, "pcs" ], [ "Olive oil", 30, "ml" ] ],
                         [ "Cut everything in chunks.", "Feta on top, oil and oregano." ] ],
      "Roast chicken with potatoes" => [ "One tray.", [ [ "Chicken breast", 600, "g" ], [ "Potatoes", 1, "kg" ], [ "Garlic", 3, "pcs" ], [ "Olive oil", 40, "ml" ] ],
                                         [ "Cut the potatoes in wedges, toss everything with oil, garlic and rosemary.", "Roast at 200° for 45 minutes, turning once." ] ],
      "Veggie omelette" => [ nil, [ [ "Eggs", 4, "pcs" ], [ "Zucchini", 1, "pcs" ], [ "Parmesan", 30, "g" ], [ "Butter", 15, "g" ] ],
                             [ "Fry the zucchini in slices.", "Pour over the beaten eggs and parmesan, fold when set." ] ],
      "Pancakes" => [ "Sunday breakfast.", [ [ "Flour", 250, "g" ], [ "Milk", 0.4, "l" ], [ "Eggs", 2, "pcs" ], [ "Butter", 30, "g" ] ],
                      [ "Whisk everything into a smooth batter and rest it 10 minutes.", "A ladle at a time in a buttered pan, flip when it bubbles." ] ],
      "Overnight oats" => [ "Made the evening before.", [ [ "Rolled oats", 160, "g" ], [ "Milk", 300, "ml" ], [ "Yogurt", 200, "g" ], [ "Bananas", 2, "pcs" ], [ "Honey", 20, "g" ] ],
                            [ "Stir oats, milk and yogurt in two jars.", "In the morning: sliced banana and honey on top." ] ],
      "Baked salmon with asparagus" => [ "For a dinner that matters.", [ [ "Salmon fillets", 400, "g" ], [ "Asparagus", 300, "g" ], [ "Potatoes", 500, "g" ], [ "Olive oil", 20, "ml" ] ],
                                         [ "Parboil the potatoes, then roast them 15 minutes.", "Add salmon and asparagus to the tray, 12 more minutes at 200°." ] ]
    }.freeze
    # Sam's own recipe, shared with Alex, who cooks it from their pantry.
    CHILI = [ "Chili con carne", "Sam's, from his mother. Double it for guests.",
              [ [ "Minced beef", 400, "g" ], [ "Black beans", 400, "g" ], [ "Canned tomatoes", 400, "g" ], [ "Onions", 1, "pcs" ], [ "Rice", 300, "g" ] ],
              [ "Brown the beef with the onion.", "Add beans, tomatoes, cumin and chili. Simmer 40 minutes.", "Serve over rice." ] ].freeze

    DINNERS = [ "Spaghetti al pomodoro", "Chicken curry", "Veggie stir-fry", "Mushroom risotto", "Red lentil soup", "Margherita pizza",
                "Beef tacos", "Roast chicken with potatoes", "Chili con carne", "Greek salad", "Veggie omelette" ].freeze
    LUNCHES = [ "Greek salad", "Veggie omelette" ].freeze
    SPECIAL = "Baked salmon with asparagus"
    # title, kind, low, high
    NIGHTS_OUT = [ [ "Pizzeria Da Michele", :eating_out, 34, 52 ], [ "Trattoria Anna Maria", :eating_out, 58, 86 ], [ "Sushi Yuzu", :ordered_in, 38, 55 ],
                   [ "Osteria dell'Orsa", :eating_out, 42, 64 ], [ "Thai Garden", :ordered_in, 30, 44 ], [ "Burger from Welldone", :ordered_in, 26, 38 ] ].freeze
    WORK_LUNCHES = [ "Bar Centrale", "Piadineria La Mora", "Mensa Greenleaf" ].freeze
    # What goes without a recipe (breakfast, coffee, a dressing): name => used in a
    # week. Alex corrects the shelf by hand on Friday and buys a pack when one runs low.
    STAPLES = { "Coffee" => 110, "Milk" => 900, "Eggs" => 3, "Bananas" => 4, "Yogurt" => 250, "Sugar" => 60, "Olive oil" => 60, "Honey" => 25 }.freeze

    def finish
      plan(@planned_until + 1, today + 7)
      special_dinner
      top_up_list
    end

    private

    def setup
      @meals = Hash.new { |meals, date| meals[date] = [] }
      @shelf = PANTRY.to_h do |name, (unit, _pack, _price, stock)|
        [ name, Ingredient.create!(profile: alex, name: name, quantity: stock, unit_name: unit, category: CATEGORY_OF.fetch(name, "pantry")) ]
      end
      @recipes = RECIPES.to_h { |name, (description, lines, steps)| [ name, recipe(alex, name, description, lines, steps) ] }
      @recipes[CHILI.first] = recipe(sam, *CHILI)
      share(@recipes[CHILI.first], with: alex)

      at(start + 2) { [ "Chicken curry", "Margherita pizza", "Pancakes", "Red lentil soup" ].each { |name| share(@recipes[name], with: sam) } }
      at(start + 20) { [ "Pancakes", "Veggie omelette", "Spaghetti al pomodoro" ].each { |name| share(@recipes[name], with: robin) } }

      first_sunday = next_weekday(start, :sunday)
      pancakes = home_meal(first_sunday, :breakfast, "Pancakes", recurrence: { frequency: "weekly" })
      follow(pancakes, done: 0.85, skipped: 0.1, late: 0)

      plan(start, first_sunday)
      shopping_list(start + 1) # the first shop, the day after moving the pantry into the app
    end

    def daily(day)
      shop(day) if @list && @list_day == day && day < today
      eat(day)
      return unless day.friday?

      STAPLES.each { |name, used| @shelf.fetch(name).adjust_stock!(-(used * rng.rand(0.7..1.2)).round(used < 10 ? 0 : -1)) }
      plan(@planned_until + 1, day + 9)
      shopping_list(day + 1)
      oil_from_the_farm(day) if (day.cweek % 13).zero?
    end

    def recipe(owner, name, description, lines, steps)
      Recipe.create!(
        profile: owner, name: name, description: description,
        recipe_ingredients_attributes: lines.map { |ingredient, quantity, unit| { ingredient_name: ingredient, quantity: quantity, unit_name: unit } },
        recipe_steps_attributes: steps.map { |instruction| { instruction: instruction } }
      )
    end

    # --- planning --------------------------------------------------------------

    def plan(from, to)
      (from..to).each { |date| plan_day(date) }
      @planned_until = [ @planned_until, to ].compact.max
    end

    def plan_day(date)
      if date.friday?
        title, kind, low, high = pick(NIGHTS_OUT)
        @meals[date] << [ meal_out(alex, date, :dinner, title, kind), amount(low, high) ]
      else
        @meals[date] << [ home_meal(date, :dinner, dinner_for(date)), nil ]
      end
      @meals[date] << [ home_meal(date, :lunch, pick(LUNCHES)), nil ] if date.saturday? && chance?(0.6)
      @meals[date] << [ home_meal(date, :breakfast, "Overnight oats"), nil ] if date.wednesday? && chance?(0.7)
      return unless (date.tuesday? || date.thursday?) && chance?(0.45)

      @meals[date] << [ meal_out(sam, date, :lunch, pick(WORK_LUNCHES), :eating_out), amount(8, 14) ]
    end

    # Never what was cooked in the last five dinners.
    def dinner_for(_date)
      @recent ||= []
      name = pick(DINNERS - @recent.last(5))
      @recent << name
      name
    end

    # Cooked at home from a recipe of the book: a series named after it.
    def home_meal(date, meal_type, recipe_name, recurrence: nil)
      meal = Meal.new(starts_on: date, details_attributes: { kind: :home, meal_type: meal_type })
      meal.details.meal_recipes.build(recipe: @recipes.fetch(recipe_name))
      create(alex, meal, recurrence: recurrence)
    end

    # Eaten out or ordered in: named after the place.
    def meal_out(who, date, meal_type, place, kind)
      create(who, Meal.new(title: place, starts_on: date, details_attributes: { kind: kind, meal_type: meal_type }))
    end

    # --- eating ----------------------------------------------------------------

    def eat(day)
      @meals.delete(day)&.each do |meal, price|
        next if day == today && meal.details.dinner? # tonight's is still to come

        roll = rng.rand
        if roll < 0.87 then eaten(meal, price)
        elsif roll < 0.94 then meal.first_occurrence.change_status!("skipped")
        end
      end
    end

    # Eaten: a home meal empties the pantry (Meal::Consumption); one out costs.
    def eaten(meal, price)
      day = meal.first_occurrence.complete!
      return if meal.details.home?

      pay(day, price, on: day.date, category: meal.fee_category, to: meal.title, method: pick(%w[card card cash]))
    end

    # --- shopping --------------------------------------------------------------

    # What the meals planned up to the Sunday after `shopping_day` need and the
    # shelf doesn't have, in whole packs, plus a staple or two.
    def shopping_list(shopping_day)
      @list_day = shopping_day
      @list = GroceryList.create!(profile: alex, name: "Weekly shop, #{I18n.l(shopping_day, format: :short)}")
      missing.each { |name, quantity| @list.grocery_list_items.create!(ingredient: @shelf.fetch(name), quantity: quantity, unit: @shelf.fetch(name).unit) }
      share(@list, with: sam)
    end

    def missing
      planned = Meal.where(profile: alex, rrule: nil, starts_on: Date.current..@planned_until).includes(details: :recipes)
      recipes = planned.select { |meal| meal.details.home? && meal.first_occurrence.pending? }.flat_map { |meal| meal.details.recipes.to_a }
      recipes += [ @recipes.fetch("Pancakes") ] * 2 # the Sunday series isn't planned meal by meal

      needs = Pantry::Availability.new(alex).for_meal(recipes).select(&:short?).to_h { |need| [ need.ingredient.name, need.needed - need.on_hand ] }
      STAPLES.each_key { |name| needs[name] ||= 0 if @shelf.fetch(name).reload.quantity < PANTRY.fetch(name).second / 2.0 }
      needs.to_h { |name, shortfall| [ name, packs(name, shortfall) ] }
    end

    def packs(name, shortfall)
      _unit, pack, = PANTRY.fetch(name)
      [ (shortfall / pack).ceil, 1 ].max * pack
    end

    def price_of(item)
      _unit, pack, price, = PANTRY.fetch(item.ingredient.name)
      item.quantity / pack * price
    end

    # Everything on the list goes in the trolley; the receipt is one expense.
    def shop(day)
      items = @list.grocery_list_items.includes(:ingredient).to_a
      items.each(&:check!)
      @list.finish!

      total = (items.sum { |item| price_of(item) } * rng.rand(0.97..1.06)) + amount(6, 19) # and what isn't food
      payer = chance?(0.25) ? sam : alex
      receipt = create(payer, Transaction.new(title: "Weekly shop", starts_on: day, details_attributes: {
                                                kind: :expense, category: :groceries, amount: total.round(2), currency: alex.household.currency, payment_method: :card, counterparty: pick(SHOPS)
                                              }))
      receipt.first_occurrence.complete!
      @list = nil
    end

    # Two litres straight from the producer once a season, with its own cost.
    def oil_from_the_farm(day)
      purchase = IngredientPurchase.create!(ingredient: @shelf.fetch("Olive oil"), profile: alex, quantity: 2, unit_name: "l", purchased_on: day)
      pay(purchase, 24, on: day, category: purchase.cost_category, to: "Frantoio Colline di Brisighella", method: "cash")
    end

    # --- the days ahead ---------------------------------------------------------

    # A dinner in the next days that the pantry can't cover yet.
    def special_dinner
      date = ((today + 2)..(today + 6)).find { |day| !day.friday? }
      meal = @meals[date].map(&:first).find { |planned| planned.details.home? && planned.details.dinner? }
      meal.details.meal_recipes.destroy_all
      meal.details.meal_recipes.create!(recipe: @recipes.fetch(SPECIAL))
    end

    # The list being shopped right now: this week's if it's still open, else a
    # top-up. Some of it is already in the basket.
    def top_up_list
      shopping_list(today) unless @list
      items = @list.grocery_list_items.includes(:ingredient).order(:id).to_a
      @list.grocery_list_items.create!(ingredient: @shelf.fetch("Honey")) if items.none? { |item| item.ingredient.name == "Honey" }
      items.reject { |item| RECIPES.fetch(SPECIAL).second.map(&:first).include?(item.ingredient.name) }
        .first((items.size * 0.4).ceil).each(&:check!)
    end
  end
end
