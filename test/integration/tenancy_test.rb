# frozen_string_literal: true

require "test_helper"

# Nothing crosses from one household to another. Every route that names a
# record, requested by Dave — of another household — about one of Alice's,
# answers 404, as if the record didn't exist: ids are sequential, so a 403
# would tell him there is one. Afterwards everything of hers is still
# there. Generated from the routes, so a new route is tested the day it is
# drawn — or fails here until it says which record it names.
#
# An id can also travel in a form's body, where no route names it. The
# models refuse to save one that isn't the person's, but the form that comes
# back refused is drawn from what was sent, so each such form is listed
# here, the calendar's included: it answers 404, or names nothing of hers
# and keeps nothing against it.
class TenancyTest < ActionDispatch::IntegrationTest
  include AlicesRecords

  # Routes that name no household's record, each with why.
  NOT_RECORDS = {
    "home" => "a section of the viewer's own home, not a record",
    "pwa" => "the installed app's own files, the offline page by language (PwaControllerTest)",
    "upload_links/public" => "a file's public link, for anyone holding its token (UploadLinks::PublicControllerTest)"
  }.freeze

  setup do
    @alice, @bob, @dave = profiles(:alice), profiles(:bob), profiles(:outsider)
    @day = Date.new(2026, 10, 6)
    build_alices_records
    sign_in @dave
    get root_path # the session holds Dave only once a request has answered (a 404 writes no cookie)
  end

  test "every route that names a record refuses someone of another household" do
    leaks = record_routes.filter_map do |route|
      path = route.format(route.required_parts.to_h { |part| [ part, route_value(route.defaults[:controller], part) ] })
      process(route.verb.downcase.to_sym, path, as: :turbo_stream)
      "#{route.verb} #{path} (#{route.defaults[:controller]}##{route.defaults[:action]}) answered #{response.status}" unless response.status == 404
    end

    assert_empty leaks
    assert @records.values.all? { |record| !record.respond_to?(:persisted?) || record.class.exists?(record.id) }, "nothing of Alice's went"
  end

  test "every id a form sends in its body refuses someone of another household" do
    leaks = forms_naming_hers.filter_map do |form, (name, request, keeps)|
      request.call
      named = response.status != 404 && response.body.match?(/\b#{Regexp.escape(name)}\b/)
      kept = keeps.call
      next unless named || kept

      "#{form} answered #{response.status}#{" naming #{name}" if named}#{" and was kept" if kept}"
    end

    assert_empty leaks
  end

  private

  # Each form whose body names a record, sent by Dave with one of Alice's:
  # the name of hers it would show, the request, and whether anything he
  # sent was kept against hers.
  def forms_naming_hers
    collection, series = @records.fetch("collections#id"), @records.fetch("event_id")
    his_restock = supply_purchase!(profile: @dave, name: "Saline")
    his_recipe = Recipe.create!(profile: @dave, name: "Stew")
    in_her_therapy = -> { SupplyPurchase.where(profile: @dave, collection: collection).exists? }
    her_series_settled = -> { series.occurrences.where.not(status: :pending).exists? }

    {
      "a restock of his supply for her therapy" => [
        collection.name,
        -> do
          post supply_purchases_path(his_restock.supply),
               params: { supply_purchase: { collection_id: collection.id, quantity_purchased: 1, purchased_on: @day } }, as: :turbo_stream
        end,
        in_her_therapy
      ],
      "his restock moved to her therapy" => [
        collection.name,
        -> { patch supply_purchase_path(his_restock), params: { supply_purchase: { collection_id: collection.id } }, as: :turbo_stream },
        in_her_therapy
      ],
      "his recipe shared with her" => [
        @alice.first_name,
        -> { post recipe_shares_path(his_recipe), params: { share: { profile_id: @alice.id } }, as: :turbo_stream },
        -> { his_recipe.recipe_shares.exists? }
      ],
      "a link asked of her" => [
        @alice.first_name,
        -> { post links_path, params: { profile_id: @alice.id }, as: :turbo_stream },
        -> { Link.where(requester: @dave).exists? }
      ],
      "her series settled from his attention list" => [
        series.title,
        -> { post attention_resolutions_path, params: { event_id: series.id }, as: :turbo_stream },
        her_series_settled
      ],
      "his attention list settled as hers" => [
        series.title,
        -> { post attention_resolutions_path, params: { member_id: @alice.id }, as: :turbo_stream },
        her_series_settled
      ]
    }.merge(calendar_forms_naming_hers(series))
  end

  # The calendar's forms name people and records in their details: whose
  # calendar a new series goes on, who a payment is with and what it is
  # about, a meal's recipes, a dose's supplies.
  def calendar_forms_naming_hers(series)
    recipe, supply = @records.fetch("recipe_id"), @records.fetch("supply_id")
    day = { date: @day.iso8601 }
    his_payments = -> { Transaction::Details.joins(:event).where(events: { profile_id: @dave.id }) }
    once = { frequency: "none" }

    {
      "his task put on her calendar" => [
        @alice.first_name,
        -> { post tasks_path, params: { owner_id: @alice.id, task: { title: "Errand", **day }, event: once }, as: :turbo_stream },
        -> { Task.where(profile: @alice, title: "Errand").exists? }
      ],
      "his payment with her" => [
        @alice.first_name,
        -> do
          post transactions_path, params: {
            transaction: { title: "Dinner", **day, details_attributes: { amount: "20", kind: "expense", category: "groceries", payment_method: "card",
                                                                         counterparty_mode: "profile", counterparty_profile_id: @alice.id } },
            event: once
          }, as: :turbo_stream
        end,
        -> { his_payments.call.where(counterparty_profile_id: @alice.id).exists? }
      ],
      "his payment about her series" => [
        series.title,
        -> do
          post transactions_path, params: {
            transaction: { title: "Fee", **day, details_attributes: { amount: "20", kind: "expense", category: "groceries", payment_method: "card",
                                                                      about_type: "Event", about_id: series.id } },
            event: once
          }, as: :turbo_stream
        end,
        -> { his_payments.call.where(about_type: "Event", about_id: series.id).exists? }
      ],
      "his meal of her recipe" => [
        recipe.name,
        -> do
          post meals_path, params: {
            meal: { **day, details_attributes: { kind: "home", meal_type: "dinner", meal_recipes_attributes: { "0" => { recipe_id: recipe.id } } } },
            event: once
          }, as: :turbo_stream
        end,
        -> { MealRecipe.where(recipe: recipe).exists? }
      ],
      "his dose from her supply" => [
        supply.name,
        -> do
          post medications_path, params: {
            medication: { title: "B12", **day, details_attributes: { kind: "pill", supply_uses_attributes: { "0" => { supply_id: supply.id, quantity: "1" } } } },
            event: once
          }, as: :turbo_stream
        end,
        -> { SupplyUse.where(supply: supply).exists? }
      ]
    }
  end

  def record_routes
    Rails.application.routes.routes.select do |route|
      controller = route.defaults[:controller]
      controller && (route.required_parts - [ :format ]).any? &&
        !controller.start_with?("admin/", "assistant/settings", "assistant/evals", "devise", "profiles/") &&
        !NOT_RECORDS.key?(controller)
    end
  end
end
