# frozen_string_literal: true

require "test_helper"

# db/seeds.rb saves the lexicon's starting languages and decides whether to
# build the demo household (Demo::Seeder, tested whole in test/lib/demo).
class SeedsTest < ActiveSupport::TestCase
  def seed(env: "test", seed: nil)
    built = false
    swapping(Demo::Seeder, :call, -> { built = true }) do
      with_env("SEED" => seed) do
        swapping(Rails, :env, -> { ActiveSupport::EnvironmentInquirer.new(env) }) do
          capture_io { load Rails.root.join("db/seeds.rb") }
        end
      end
    end
    built
  end

  test "builds the demo household when there is none" do
    Household.where(slug: Demo::Seeder::SLUG).destroy_all
    assert seed
  end

  test "leaves an existing demo household alone, unless asked to rebuild it" do
    Household.create!(name: "Demo", slug: Demo::Seeder::SLUG) unless Demo::Seeder.household
    assert_not seed
    assert seed(seed: "demo")
  end

  test "builds no demo household in production unless asked" do
    Household.where(slug: Demo::Seeder::SLUG).destroy_all
    assert_not seed(env: "production")
    assert seed(env: "production", seed: "demo")
  end

  test "saves the lexicon's starting languages everywhere, production included" do
    LexiconLanguage.where(code: "it").delete_all
    seed(env: "production")

    assert_equal Lexicon::Config.defaults.keys.sort, LexiconLanguage.pluck(:code).sort
  end
end
