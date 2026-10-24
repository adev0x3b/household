# frozen_string_literal: true

require "test_helper"

# Sharing a thing, or stopping, is its owner's alone — whatever the thing,
# whoever else can see or change it — and a file only once it is all there.
class SharePolicyTest < ActiveSupport::TestCase
  def share?(user, thing) = SharePolicy.new(user, thing).share?

  test "the owner shares; whoever it is shared with, or anyone else, doesn't" do
    photo = uploads(:photo) # bob's, shared with alice
    assert share?(profiles(:bob), photo)
    assert_not share?(profiles(:alice), photo)
    assert_not share?(profiles(:carol), photo)

    book = books(:hail_mary) # bob's
    assert share?(profiles(:bob), book)
    assert_not share?(profiles(:alice), book)
  end

  test "a shelf is shared by the person it belongs to" do
    shelf = profiles(:alice).bookshelf!

    assert share?(profiles(:alice), shelf)
    assert_not share?(profiles(:bob), shelf)
  end

  test "a file still coming isn't shared yet, not even by its owner" do
    assert_not share?(profiles(:alice), uploads(:backup))
  end
end
