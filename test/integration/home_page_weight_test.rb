# frozen_string_literal: true

require "test_helper"

# What home costs: a fixed number of queries, however much a
# household keeps. Its pages read per kind of item and per list,
# never per series, day or row, so a household with twice of everything
# costs the same, and the overview stays within its budget. The N+1 check
# catches a query repeated per record; this catches the rest: a query
# added for each series a page lists, or a fixed one nobody meant to add.
class HomePageWeightTest < ActionDispatch::IntegrationTest
  # The overview's queries on the test's household, the query cache's
  # answers included. Lower it when a change saves some; raising it is a
  # decision, said with what the page then costs in the commit that raises it.
  BUDGET = 73

  PAGES = [ "overview", *Views::Home::Pages::SECTIONS.keys ].freeze

  setup do
    @profile = profiles(:carol)
    sign_in @profile
  end

  test "twice the series, days and lists of every kind cost the same queries on every home page" do
    a_month_of_everything!(1)
    before = PAGES.index_with { queries_for(_1) }
    a_month_of_everything!(2)
    after = PAGES.index_with { queries_for(_1) }

    assert_equal before, after
  end

  test "the overview stays within its budget" do
    a_month_of_everything!(1)
    assert_operator queries_for("overview"), :<=, BUDGET
  end

  private

  def path_for(page) = page == "overview" ? root_path : home_section_path(section: page)

  # A second request's queries: the first fills what a visit keeps (the
  # session), as a reader's first page of the day would. Every query the
  # page asks for counts, the query cache's answers too: whether the cache
  # catches a repeat depends on the order rows come back in (the same ids,
  # listed in another order, are another query), so leaving its answers out
  # would make the count a matter of luck.
  def queries_for(page)
    get path_for(page)
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path_for(page) }
    assert_response :success
    count
  end

  # One of each thing home reads, around today: repeating series of every
  # kind with done, skipped and upcoming days, a visit's fee, doses that draw
  # supplies, meals from recipes, lab values, money both ways, stock that
  # runs low or expires, a grocery list to buy.
  def a_month_of_everything!(n)
    today = Date.current
    chores = weekly_event(profile: @profile, type: Task, starts_on: today - 20, title: "Chores #{n}")
    day!(chores, date: today - 13, status: :completed)
    day!(chores, date: today - 6, status: :skipped)
    task!(profile: @profile, date: today + 2, title: "Call #{n}")

    visit = appointment!(profile: @profile, date: today - 3, title: "Visit #{n}", counterpart: "Rossi")
    expense!(profile: @profile, date: today - 3, cents: 5_000, about: visit, title: "Fee #{n}")
    appointment!(profile: @profile, date: today + 4, title: "Dinner #{n}", kind: :social)

    supply = supply_purchase!(profile: @profile, name: "Needles #{n}", quantity: 10, remaining: 2, threshold: 5, expires_on: today + 10,
                              purchased_on: today - 30).supply
    dose = timed_medication!(profile: @profile, starts_on: today - 20, times: %w[08:00 20:00], name: "Metformin #{n}")
    dose.event.details.replace_uses!([ [ supply.id, "1" ] ])
    day!(dose.event, date: today - 2, time: "08:00", status: :completed)

    recipe = recipe_with(@profile, "Soup #{n}", [ "Lentils #{n}", 200, "g" ])
    meal_on(@profile, today - 1, recipes: [ recipe ], status: :completed)
    meal_on(@profile, today + 1, recipes: [ recipe ], meal_type: :dinner)

    lab_result!(profile: @profile, date: today - 5, values: { "Glucose #{n}" => "90", "Ferritin #{n}" => "40" }, status: :completed)

    income!(profile: @profile, date: today - 10, cents: 200_000, title: "Salary #{n}")
    expense!(profile: @profile, date: today - 4, cents: 3_000, category: :groceries, title: "Market #{n}")
    ingredient_purchase!(profile: @profile, name: "Flour #{n}", purchased_on: today - 8)

    list = GroceryList.create!(profile: @profile, name: "Saturday #{n}")
    list.grocery_list_items.create!(ingredient_name: "Milk #{n}", quantity: 1)
  end
end
