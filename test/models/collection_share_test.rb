# frozen_string_literal: true

require "test_helper"

class CollectionShareTest < ActiveSupport::TestCase
  test "is unique per collection and person" do
    duplicate = CollectionShare.new(collection: collections(:b12), profile: profiles(:bob))
    assert_not duplicate.valid?
  end

  test "cannot share with the owner" do
    share = CollectionShare.new(collection: collections(:b12), profile: profiles(:alice))
    assert_not share.valid?
    assert_predicate share.errors[:profile_id], :any?
  end

  test "never leaves the household" do
    share = CollectionShare.new(collection: collections(:b12), profile: profiles(:outsider))
    assert_not share.valid?
    assert_predicate share.errors[:profile], :any?
  end
end
