# frozen_string_literal: true

require "test_helper"

class Admin::PlatformPolicyTest < ActiveSupport::TestCase
  test "the admin alone, never a household's owner" do
    admin = profiles(:carol).tap { _1.update!(role: :admin) }

    assert_predicate Admin::PlatformPolicy.new(admin, :platform), :manage?
    assert_not Admin::PlatformPolicy.new(profiles(:alice), :platform).manage?
    assert_not Admin::PlatformPolicy.new(profiles(:bob), :platform).manage?
  end
end
