# frozen_string_literal: true

require "test_helper"

# The index cards share one rule for their actions: the name opens the
# thing, at most two round buttons sit on the card, and deleting waits
# behind "more".
class Views::CardsTest < ActiveSupport::TestCase
  test "a card's name opens it, and no button repeats the name's link" do
    cards = {
      routes.recipe_path(recipes(:roast_chicken)) => Views::Recipes::Card.new(recipe: recipes(:roast_chicken), viewer: profiles(:alice)),
      routes.collection_path(collections(:b12)) => Views::Collections::Card.new(collection: collections(:b12), viewer: profiles(:alice)),
      routes.grocery_list_path(grocery_lists(:weekly_shop)) => Views::GroceryLists::Card.new(grocery_list: grocery_lists(:weekly_shop), viewer: profiles(:alice)),
      routes.analyte_path(analytes(:glucose)) => Views::Analytes::Card.new(analyte: analytes(:glucose))
    }

    cards.each do |path, view|
      card = parse(view)

      assert card.at_css(".card__header a[href='#{path}']"), "#{view.class} has no name linking to #{path}"
      assert_empty card.css(".card__actions a.item-action[href='#{path}']:not([data-turbo-method])"), "#{view.class} repeats its link as a button"
      assert_operator card.css(".card__actions > .item-action, .card__actions > .item-menu").size, :<=, 2, view.class.name
    end
  end

  test "an analyte card edits on the card and deletes behind More" do
    card = parse(Views::Analytes::Card.new(analyte: analytes(:glucose)))

    labels = card.css(".card__actions > a.item-action").map { |action| action["aria-label"] }
    assert_equal [ I18n.t("analytes.card.edit") ], labels
    assert_equal [ I18n.t("analytes.card.destroy") ], card.css(".item-menu__entry--danger span").map(&:text)
  end

  private

  def routes = Rails.application.routes.url_helpers

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
end
