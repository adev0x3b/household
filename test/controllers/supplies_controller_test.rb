# frozen_string_literal: true

require "test_helper"

# Supplies belong to a profile; someone a therapy (a Healthcare collection)
# is shared with sees (and restocks) the supplies bought for it, but only
# the owner changes them.
class SuppliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob) # Alice's B12 collection is shared with him
    @carol = profiles(:carol)
    @needles = supply_purchase!(profile: @alice, name: "Needles", collection: collections(:b12)).supply
    @gauze = supply_purchase!(profile: @alice, name: "Gauze").supply
  end

  test "the index lists the profile's own supplies, never anyone else's" do
    sign_in @carol
    supply_purchase!(profile: @carol, name: "Saline")

    get supplies_path

    assert_response :success
    assert_includes response.body, "Saline"
    assert_not_includes response.body, "Needles"
    assert_not_includes response.body, "Gauze"
  end

  test "a shared therapy's supplies show up, without the owner's edit and delete" do
    sign_in @bob

    get supplies_path

    assert_includes response.body, "Needles"
    assert_not_includes response.body, "Gauze"
    assert_select "a[href=?]", Rails.application.routes.url_helpers.edit_supply_path(@needles), false
    assert_select "a[href=?]", Rails.application.routes.url_helpers.new_supply_purchase_path(@needles)
  end

  test "someone else's supply is not found" do
    sign_in @carol
    get supplies_path # a 404 first would drop the test sign-in before its session is saved

    get edit_supply_path(@gauze), as: :turbo_stream
    assert_response :not_found
    patch supply_path(@gauze), params: { supply: { name: "Mine now" } }, as: :turbo_stream
    assert_response :not_found
    delete supply_path(@gauze), as: :turbo_stream
    assert_response :not_found
    get supply_purchases_path(@gauze)
    assert_response :not_found
    get new_supply_purchase_path(@gauze), as: :turbo_stream
    assert_response :not_found

    assert_equal "Gauze", @gauze.reload.name
  end

  test "a shared therapy's supply can't be renamed or deleted by the one it's shared with" do
    sign_in @bob

    patch supply_path(@needles), params: { supply: { name: "Renamed" } }, as: :turbo_stream
    assert_no_difference -> { Supply.count } do
      delete supply_path(@needles), as: :turbo_stream
    end

    assert_equal "Needles", @needles.reload.name
  end

  test "a supply a medication uses is refused with a reason; one nothing uses goes back to the list" do
    sign_in @alice
    dose = medication!(profile: @alice, date: Date.current)
    dose.event.details.supply_uses.create!(supply: @needles, quantity: 1)

    assert_no_difference -> { Supply.count } do
      delete supply_path(@needles), as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_toast "Needles can't be deleted while a medication uses it."

    delete supply_path(@gauze), headers: submitted_from(supplies_path)
    assert_redirected_to supplies_path
    assert_not Supply.exists?(@gauze.id)
  end

  test "a purchase a dose was taken from can be deleted, and the dose keeps what it drew" do
    sign_in @alice
    purchase = @gauze.supply_purchases.sole
    dose = medication!(profile: @alice, date: Date.current)
    dose.event.details.supply_uses.create!(supply: @gauze, quantity: 2)
    dose.complete!

    delete supply_purchase_path(purchase), headers: submitted_from(supply_purchases_path(@gauze))

    assert_redirected_to supply_purchases_path(@gauze)
    assert_not SupplyPurchase.exists?(purchase.id)
    assert_equal [ [ @gauze.id, nil, 2 ] ], dose.supply_consumptions.reload.pluck(:supply_id, :supply_purchase_id, :quantity)
  end

  test "a new supply belongs to whoever adds it, and names are unique per profile" do
    sign_in @carol
    get new_supply_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='supply[name]']", supplies_path

    assert_difference -> { @carol.supplies.count }, 1 do
      post supplies_path, params: { supply: { name: "Gauze", category: "consumable", unit_label: "pcs" } }, as: :turbo_stream
    end
    assert_equal 2, Supply.where(name: "Gauze").count
  end

  test "updating a purchase never moves it to another supply or someone else's therapy" do
    sign_in @alice
    purchase = @gauze.supply_purchases.sole
    carols = supply_purchase!(profile: @carol, name: "Saline").supply

    patch supply_purchase_path(purchase), as: :turbo_stream, params: {
      supply_purchase: { supply_id: carols.id, collection_id: collections(:fibromyalgia).id, quantity_purchased: 3 }
    }

    purchase.reload
    assert_equal @gauze, purchase.supply
    assert_nil purchase.collection
    assert_equal 3, purchase.quantity_purchased
  end

  test "a purchase goes in one of your therapies, with its cost; its history finds it by either" do
    sign_in @alice
    purchase = @gauze.supply_purchases.sole

    get edit_supply_purchase_path(purchase), as: :turbo_stream
    assert_select "select[name='supply_purchase[collection_id]'] option[value=?]", collections(:b12).id.to_s

    patch supply_purchase_path(purchase), as: :turbo_stream, params: {
      supply_purchase: { collection_id: collections(:b12).id, quantity_purchased: 10 },
      transaction: { amount: "12", payment_method: "card", counterparty_mode: "text", counterparty: "Farmacia Centrale" }
    }
    assert_redirected_to supply_purchases_path(@gauze)
    purchase.reload
    assert_equal collections(:b12), purchase.collection
    assert_equal 1200, purchase.cost.details.amount_cents
    assert_equal "healthcare", purchase.cost.details.category

    get supply_purchases_path(@gauze, q: "Farmacia")
    assert_select ".supply-purchase-row__date", text: /Farmacia Centrale/, message: "a row shows the shop the search matched"
    get supply_purchases_path(@gauze, q: "B12")
    assert_select ".supply-purchase-row__date", text: /#{collections(:b12).name}/
    assert_select ".supply-purchase-row__cost-label", text: /12/
  end

  test "the history is a page with the top bar's search and Buy more; a row's change goes back to it" do
    sign_in @alice
    purchase = @gauze.supply_purchases.sole

    get supply_purchases_path(@gauze)
    assert_response :success
    assert_select "h1.page-title", I18n.t("supplies.history.title", name: "Gauze")
    assert_select "a.supply-history__back[href=?]", supplies_path
    assert_select ".navbar-topbar-controls form[action=?] input[name=q]", supply_purchases_path(@gauze)
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-stream]", new_supply_purchase_path(@gauze)
    assert_select "turbo-frame##{Views::SupplyPurchases::List::FRAME_ID} .supply-purchase-row a.item-action[href=?]", edit_supply_purchase_path(purchase)

    get supply_purchases_path(@gauze, q: "nothing like it"), headers: { "Turbo-Frame" => Views::SupplyPurchases::List::FRAME_ID }
    assert_select "input[type=search]", false, "a search answers with the results alone"
    assert_select ".empty-state"

    page = "http://www.example.com#{supply_purchases_path(@gauze, page: 1)}"
    get new_supply_purchase_path(@gauze), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", supply_purchases_path(@gauze)
    assert_select "form input[name='supply_purchase[supply_id]']", false, "the supply is the form's address, not a field of it"
    post supply_purchases_path(@gauze), as: :turbo_stream, headers: { "Referer" => page },
                                        params: { supply_purchase: { quantity_purchased: 5, quantity_remaining: 5, purchased_on: "2026-10-01" } }
    assert_redirected_to page
    assert_equal I18n.t("supply_purchases.notices.created"), flash[:success]

    assert_difference -> { @gauze.supply_purchases.count }, -1 do
      delete supply_purchase_path(purchase), as: :turbo_stream, headers: { "Referer" => page }
    end
    assert_redirected_to page
    assert_response :see_other
  end

  test "a new supply's first purchase is saved with its cost, or the supply isn't saved at all" do
    sign_in @carol
    params = { supply: { name: "Gauze", category: "consumable", unit_label: "pcs",
                         supply_purchases_attributes: { "0" => { quantity_purchased: 20, purchased_on: "2026-10-01" } } } }

    post supplies_path, as: :turbo_stream, params: params.merge(transaction: { amount: "8", payment_method: "card" })
    purchase = @carol.supplies.find_by!(name: "Gauze").supply_purchases.sole
    assert_equal [ 800, "healthcare" ], [ purchase.cost.details.amount_cents, purchase.cost.details.category ]

    assert_no_difference [ -> { Supply.count }, -> { Transaction.count } ] do
      post supplies_path, as: :turbo_stream, params: params.deep_merge(supply: { name: "Swabs" }, transaction: { amount: "8", payment_method: "" })
    end
    assert_select "form[action=?]", supplies_path
    assert_select "form input[name=_method]", false, "a failed new supply is a new form again, not an edit"
  end

  test "a restock whose cost can't be saved isn't saved, and its form posts as new again" do
    sign_in @alice

    assert_no_difference [ -> { @gauze.supply_purchases.count }, -> { Transaction.count } ] do
      post supply_purchases_path(@gauze), as: :turbo_stream, params: {
        supply_purchase: { quantity_purchased: 5, purchased_on: "2026-10-01" },
        transaction: { amount: "8", payment_method: "" }
      }
    end
    assert_select "form[action=?]", supply_purchases_path(@gauze)
    assert_select "form input[name=_method]", false
  end
end
