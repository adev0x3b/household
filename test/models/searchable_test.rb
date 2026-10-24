# frozen_string_literal: true

require "test_helper"

class SearchableTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:alice)
  end

  test "matches part of the name, ignoring case and accents" do
    risotto = Recipe.create!(profile: @profile, name: "Risotto ai funghi Porcìni")

    assert_includes Recipe.search("PORCINI"), risotto
    assert_includes Recipe.search("funghi porc"), risotto
  end

  test "every word must match" do
    risotto = Recipe.create!(profile: @profile, name: "Risotto ai funghi")

    assert_includes Recipe.search("funghi risotto"), risotto
    assert_not_includes Recipe.search("funghi pancakes"), risotto
  end

  test "a blank query finds everything" do
    assert_equal Recipe.count, Recipe.search(nil).count
    assert_equal Recipe.count, Recipe.search("  ").count
  end

  test "LIKE wildcards are matched literally" do
    Recipe.create!(profile: @profile, name: "Pancakes 100%")

    assert_equal [ "Pancakes 100%" ], Recipe.search("100%").pluck(:name)
    assert_empty Recipe.search("_ancakes")
  end
end
