# frozen_string_literal: true

require "test_helper"

# The share addresses of each kind of shareable, as the routes name them.
class Shares::PathsTest < ActiveSupport::TestCase
  test "a thing's shares and one share on it are under the thing's own address" do
    recipe = recipes(:roast_chicken)
    share = recipe_shares(:roast_chicken_bob)
    paths = Shares::Paths.new(recipe)

    assert_equal "/recipes/#{recipe.id}/shares", paths.shares
    assert_equal "/recipes/#{recipe.id}/shares/#{share.id}", paths.share(share)
  end

  test "a series is shared as an event whatever its kind" do
    task = events(:groceries)
    share = EventShare.new(id: 7)

    assert_kind_of Task, task
    assert_equal "/events/#{task.id}/shares", Shares::Paths.new(task).shares
    assert_equal "/events/#{task.id}/shares/7", Shares::Paths.new(task).share(share)
  end

  test "the shelf is the signed-in person's one bookshelf, never numbered" do
    shelf = profiles(:alice).bookshelf!
    share = BookshelfShare.new(id: 3)

    assert_equal "/bookshelf/shares", Shares::Paths.new(shelf).shares
    assert_equal "/bookshelf/shares/3", Shares::Paths.new(shelf).share(share)
  end

  test "the key names the thing among shareables by its base kind" do
    assert_equal "event-#{events(:groceries).id}", Shares::Paths.key(events(:groceries))
    assert_equal "recipe-#{recipes(:roast_chicken).id}", Shares::Paths.key(recipes(:roast_chicken))
  end
end
