# frozen_string_literal: true

require "test_helper"

class Uploads::IndexQueryTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @before = query.counts
    @mine = keep_file(@alice, name: "zebra-invoice.pdf")
    keep_file(@alice, name: "zebra-notes.txt")
    @theirs = keep_file(@bob, name: "zebra-bob.pdf")
    Shares::Create.call(@theirs, with: @alice, by: @bob)
    keep_file(@bob, name: "zebra-private.txt")
  end

  test "counts each scope of what the viewer can see" do
    assert_equal({ "all" => @before["all"] + 3, "mine" => @before["mine"] + 2, "shared" => @before["shared"] + 1 }, query.counts)
  end

  test "narrows to a scope and a search, and ignores a scope that isn't one" do
    assert_equal [ @theirs ], query(search: "zebra", scope: "shared").uploads.to_a
    assert_equal [ @mine ], query(search: "zebra-invoice", scope: "mine").uploads.to_a
    assert_equal "all", query(scope: "everyone's").scope
  end

  private

  def query(search: nil, scope: nil) = Uploads::IndexQuery.new(viewer: @alice, search: search, scope: scope, page: 1)
end
