# frozen_string_literal: true

require "test_helper"

class Shares::CreateTest < ActiveSupport::TestCase
  setup do
    @alice, @carol = profiles(:alice), profiles(:carol)
    @recipe = recipes(:roast_chicken)
  end

  test "inside a caller's transaction the person hears nothing until it commits" do
    ActiveRecord::Base.transaction do
      assert_predicate Shares::Create.call(@recipe, with: @carol, by: @alice), :success?
      assert_empty @carol.notifications.shared, "told before the share was committed"
    end

    assert_equal([ [ @recipe, @alice ] ], @carol.notifications.shared.map { [ _1.subject, _1.actor ] })
  end

  test "rolled back, it is never heard of" do
    ActiveRecord::Base.transaction do
      Shares::Create.call(@recipe, with: @carol, by: @alice)
      raise ActiveRecord::Rollback
    end

    assert_not @recipe.recipe_shares.exists?(profile: @carol)
    assert_empty @carol.notifications
  end

  test "a share the thing can't have is a failure carrying its errors, and nothing more" do
    result = Shares::Create.call(@recipe, with: @alice, by: @alice)

    assert_predicate result, :failure?
    assert_equal :invalid, result.error
    assert result.share.errors.of_kind?(:profile_id, :invalid), "never with the owner"
    assert_empty @alice.notifications.shared
  end
end
