# frozen_string_literal: true

require "test_helper"

# Supplies saved in Italian, named in English (and the other way round):
# the lexicon finds the saved one instead of reporting it unknown — or, for a
# purchase, instead of quietly starting a second supply.
class Assistant::SupplyNamesAcrossLanguagesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 3, 12)
    import_lexicons
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.b12_weekly(@profile)
  end

  teardown { travel_back }

  def supply(name) = Supply.find_by!(profile: @profile, name: name)
  def in_stock(name) = SupplyPurchase.where(supply: supply(name)).sum(:quantity_remaining).to_i

  test "\"needle\" and \"syringe\" for a dose go on the saved Aghi and Siringhe" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamina",
                                             uses: [ { supply: "needle" }, { supply: "syringe" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Aghi × 1", "Cobalamina 0.12 ml", "Siringhe × 1" ], result[:data][:saved].first[:uses].sort
  end

  test "needles bought add to the saved Aghi, no second supply" do
    result = run_tool(:record_purchases, @chat, payment_method: "card", therapy: "B12", date: "2026-10-02",
                                                items: [ { supply: "needles", quantity: 100, amount: 10 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 300, in_stock("Aghi")
    assert_nil Supply.find_by(profile: @profile, name: "needles")
  end

  test "two supplies the word fits equally are not guessed between" do
    thin = @profile.supplies.create!(name: "Aghi sottili", category: :consumable, unit_label: "pieces")
    SupplyPurchase.create!(supply: thin, profile: @profile, quantity_purchased: 50, quantity_remaining: 50, purchased_on: Date.current)
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamina", uses: [ { supply: "needle" } ])

    assert_equal false, result[:ok], result.inspect
    assert_match(/no supply called needle .*Aghi, Aghi sottili/, result[:error])
  end
end
