# frozen_string_literal: true

require "test_helper"

class IngredientPurchasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    @flour = ingredients(:flour) # 2.5 kg
    sign_in @profile
  end

  def buy(ingredient_purchase: {}, transaction: nil)
    params = { ingredient_purchase: { quantity: "1", purchased_on: "2026-10-01" }.merge(ingredient_purchase) }
    params[:transaction] = transaction if transaction
    post ingredient_purchases_path(@flour), as: :turbo_stream, params: params
  end

  test "new opens the purchase modal" do
    get new_ingredient_purchase_path(@flour), as: :turbo_stream
    assert_response :success
    assert_includes response.body, "ingredient_purchase[quantity]"
  end

  test "buying without a cost adds stock and no transaction" do
    assert_difference -> { IngredientPurchase.count }, 1 do
      assert_no_difference -> { Transaction.count } do
        buy
      end
    end
    assert_redirected_to ingredient_purchases_path(@flour)
    assert_response :see_other
    assert_in_delta(3.5, @flour.reload.quantity)
  end

  test "a purchase made on a page goes back to it, refreshed in place, with what was done" do
    post ingredient_purchases_path(@flour), as: :turbo_stream, headers: { "Referer" => "http://www.example.com#{ingredients_path}" },
                                            params: { ingredient_purchase: { quantity: "1", purchased_on: "2026-10-01" } }

    assert_redirected_to ingredients_path
    assert_response :see_other
    assert_equal I18n.t("ingredient_purchases.notices.created"), flash[:success]
  end

  test "buying with a cost attaches a groceries expense" do
    assert_difference -> { Transaction.count }, 1 do
      buy(transaction: { amount: "4.50", payment_method: "card", counterparty_mode: "text", counterparty: "Lidl" })
    end
    assert_response :see_other

    purchase = IngredientPurchase.order(:id).last
    cost = purchase.costs.sole
    assert_predicate cost.details, :groceries?
    assert_predicate cost.details, :expense?
    assert_equal 450, cost.details.amount_cents
    assert_equal "Lidl", cost.details.counterparty
    assert_equal "Groceries: 1 kg Flour", cost.title
    assert_predicate cost, :completed?, "a purchase is logged once bought, so it's paid"
  end

  test "an invalid cost rolls the purchase and the stock back" do
    assert_no_difference -> { IngredientPurchase.count } do
      buy(transaction: { amount: "0", payment_method: "card", counterparty_mode: "text" })
    end
    assert_in_delta(2.5, @flour.reload.quantity)
  end

  test "an amount without a payment method brings the form back asking for one" do
    assert_no_difference -> { IngredientPurchase.count } do
      buy(transaction: { amount: "4.50", payment_method: "", counterparty_mode: "text" })
    end

    assert_response :unprocessable_content
    assert_form_error "Payment method can't be blank"
  end

  test "a unit that doesn't convert is refused and shows the reason" do
    assert_no_difference -> { IngredientPurchase.count } do
      buy(ingredient_purchase: { unit_name: "pcs" })
    end
    assert_response :unprocessable_content
    assert_includes response.body, "kg"
  end

  test "can't buy for someone else's ingredient" do
    assert_no_difference -> { IngredientPurchase.count } do
      post ingredient_purchases_path(ingredients(:olive_oil)), as: :turbo_stream,
                                                               params: { ingredient_purchase: { quantity: "1", purchased_on: "2026-10-01" } }
    end
    assert_response :not_found
    assert_equal 1, ingredients(:olive_oil).reload.quantity
  end

  test "updating the quantity moves the stock and adds a cost" do
    purchase = @flour.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.new(2026, 10, 1))

    patch ingredient_purchase_path(purchase), as: :turbo_stream, params: {
      ingredient_purchase: { quantity: "2", purchased_on: "2026-10-01" },
      transaction: { amount: "3", payment_method: "cash", counterparty_mode: "text" }
    }

    assert_response :see_other
    assert_in_delta(4.5, @flour.reload.quantity)
    assert_equal 300, purchase.costs.sole.details.amount_cents
  end

  test "destroying takes the stock back and keeps the cost as an unattached expense" do
    purchase = @flour.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.new(2026, 10, 1))
    cost = Transactions::SetCost.call(
      purchase, date: purchase.purchased_on, title: "x", amount: "2", payment_method: "card", category: :groceries
    ).cost

    delete ingredient_purchase_path(purchase), as: :turbo_stream

    assert_response :see_other
    assert_in_delta(2.5, @flour.reload.quantity)
    assert Occurrence.exists?(cost.id)
    assert_nil cost.event.details.reload.about
  end

  test "another profile's purchase can't be edited or deleted" do
    purchase = @flour.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.current)
    sign_out :profile
    sign_in profiles(:bob)

    assert_no_difference -> { IngredientPurchase.count } do
      delete ingredient_purchase_path(purchase), as: :turbo_stream
    end
    assert_response :not_found
  end
end
