# frozen_string_literal: true

require "test_helper"

class Assistant::ChatPolicyTest < ActiveSupport::TestCase
  test "a chat is its owner's, photos included where the installation has pictures on" do
    chat = assistant_chat(profiles(:alice))

    assert_predicate Assistant::ChatPolicy.new(profiles(:alice), chat), :show?
    assert_predicate Assistant::ChatPolicy.new(profiles(:alice), chat), :attach?
    assert_not Assistant::ChatPolicy.new(profiles(:bob), chat).show?
    assert_not Assistant::ChatPolicy.new(profiles(:bob), chat).attach?
    with_env("PICTURES" => "off") { assert_not Assistant::ChatPolicy.new(profiles(:alice), chat).attach? }
  end
end
