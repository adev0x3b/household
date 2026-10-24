# frozen_string_literal: true

require "test_helper"

# Every kind of series (Event.types) is drawn by its card and edited in its
# form, each listed on the view side.
class Views::Calendar::CardsTest < ActiveSupport::TestCase
  test "every kind of series has its card, its icon and its form" do
    Event.types.each do |kind|
      assert_operator Views::Calendar::Cards.for(kind), :<, Views::Calendar::Cards::Base, kind.name
      assert_match(/\Afa-/, Views::Calendar::Cards.for(kind).icon, kind.name)
      assert_operator Views::Occurrences::Forms.for(kind), :<, Views::Occurrences::Form, kind.name
    end
    assert_equal Event.types, Views::Calendar::Cards::BY_KIND.keys, "no card for a kind that isn't one"
  end

  test "a purchase the assistant drafts has a form too, and a kind with none is an error, not a guess" do
    assert_equal Views::SupplyPurchases::Modals::Form, Views::Occurrences::Forms.for(SupplyPurchase)
    assert_equal Views::IngredientPurchases::Modals::Form, Views::Occurrences::Forms.for(IngredientPurchase)
    assert_raises(KeyError) { Views::Occurrences::Forms.for(Recipe) }
    assert_raises(KeyError) { Views::Calendar::Cards.for(Recipe) }
  end

  test "an appointment's icon is its kind's" do
    visit = events(:endocrinologist)
    interview = Appointment.new(details_attributes: { kind: :work })

    assert_equal "fa-user-doctor", Views::Calendar::Cards.icon_of(visit)
    assert_equal "fa-briefcase", Views::Calendar::Cards.icon_of(interview)
    assert_equal "fa-user-doctor", Views::Calendar::Cards::AppointmentCard.icon, "a new one starts as a visit"
    assert_equal "fa-clipboard-list", Views::Calendar::Cards.icon_of(events(:groceries))
  end

  test "an amount is drawn with the way it went" do
    assert_equal "-€42.00", Components::SignedMoney.new(cents: -4200, currency: "EUR").call
    assert_equal "+€1,200.00", Components::SignedMoney.new(cents: 120_000, currency: "EUR").call
  end

  test "an injection's position is said area first in Italian and side first in English" do
    day = occurrences(:methotrexate_taken)
    position = ->(viewer) { Nokogiri::HTML5.fragment(ApplicationController.render(Views::Calendar::Cards::MedicationCard.new(occurrence: day, viewer: viewer), layout: false)).at_css(".medication-card__position")&.text }

    assert_equal "Right thigh", position.call(profiles(:alice))
    assert_equal "Coscia destra", I18n.with_locale(:it) { position.call(profiles(:alice)) }
  end
end
