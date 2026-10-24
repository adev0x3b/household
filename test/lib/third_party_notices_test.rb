# frozen_string_literal: true

require "test_helper"

# THIRD_PARTY_NOTICES.md is the one place that says whose work the repository
# carries, so a vendored file without a row, or a row pointing nowhere, fails.
class ThirdPartyNoticesTest < ActiveSupport::TestCase
  VENDORED = %w[
    vendor/javascript/* vendor/assets/wasm/* vendor/assets/icons/* vendor/fontawesome test/vendor/*
  ].freeze

  test "every vendored file or directory has a row in the notices" do
    listed = notice_paths

    VENDORED.flat_map { |pattern| Dir.glob(Rails.root.join(pattern)) }.each do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s

      assert listed.any? { |entry| covers?(entry, relative) },
             "#{relative} is vendored but THIRD_PARTY_NOTICES.md does not list it"
    end
  end

  test "every path the notices name exists" do
    notice_paths.each do |entry|
      matches = Dir.glob(Rails.root.join(entry))

      assert_predicate matches, :any?, "THIRD_PARTY_NOTICES.md names #{entry}, which does not exist"
    end
  end

  test "every license text is named by the notices" do
    notices = Rails.root.join("THIRD_PARTY_NOTICES.md").read

    Dir.glob(Rails.root.join("licenses/*")).each do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s

      assert_includes notices, relative
    end
  end

  test "the tests and what they vendor stay out of the image" do
    assert_includes Rails.root.join(".dockerignore").read.lines.map(&:strip), "/test"
  end

  private

  def covers?(entry, relative)
    return relative.start_with?(entry) || entry.chomp("/") == relative if entry.end_with?("/")

    File.fnmatch?(entry, relative)
  end

  def notice_paths
    Rails.root.join("THIRD_PARTY_NOTICES.md").read.scan(/`((?:vendor|test|licenses)\/[^`]+)`/).flatten.uniq
  end
end
