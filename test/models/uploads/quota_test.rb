# frozen_string_literal: true

require "test_helper"

# A household's room for files: what its members keep, whoever of them.
class Uploads::QuotaTest < ActiveSupport::TestCase
  test "counts every member's files, an upload still coming at its declared size" do
    quota = Uploads::Quota.new(households(:example))

    assert_equal 1016, quota.used # 11 + 5 + 1000 declared
    assert_equal Platform.files_quota - 1016, quota.left
  end

  test "what fits is what is left, never less than nothing" do
    with_env("FILES_QUOTA" => "1000") do
      quota = Uploads::Quota.new(households(:example))

      assert_equal [ 1000, 0 ], [ quota.total, quota.left ]
      assert quota.fits?(0)
      assert_not quota.fits?(1)
    end

    with_env("FILES_QUOTA" => "2KB") do
      quota = Uploads::Quota.new(households(:example))

      assert quota.fits?(1032)
      assert_not quota.fits?(1033)
    end
  end
end
