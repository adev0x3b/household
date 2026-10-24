# frozen_string_literal: true

require "test_helper"

# A path to live under, as the app reads it: a leading slash, no trailing one; empty for the root.
class Provision::MountTest < ActiveSupport::TestCase
  test "normalises what is typed" do
    assert_equal "", Provision::Mount.normalise(nil)
    assert_equal "", Provision::Mount.normalise("")
    assert_equal "", Provision::Mount.normalise("/")
    assert_equal "", Provision::Mount.normalise(" // ")
    assert_equal "/love", Provision::Mount.normalise("love")
    assert_equal "/love", Provision::Mount.normalise("/love/")
    assert_equal "/my/home", Provision::Mount.normalise(" my/home/ ")
  end
end
