# frozen_string_literal: true

require "test_helper"

class Releases::VersionTest < ActiveSupport::TestCase
  test "a release's tag is v, the year, the month unpadded and the number from 1" do
    assert_equal Releases::Version.new(2026, 11, 1), Releases::Version.parse("v2026.11.1")
    assert_equal "v2026.3.12", Releases::Version.parse("v2026.3.12").tag
    assert_equal "2026.3.12", Releases::Version.parse("v2026.3.12").to_s
    %w[2026.11.1 v2026.03.1 v2026.13.1 v2026.11.0 v2026.11 v2026.11.1-rc1 stable].each do |tag|
      assert_nil Releases::Version.parse(tag), tag
    end
  end

  test "versions order by year, month and number, as numbers" do
    versions = %w[v2026.10.2 v2026.9.3 v2026.10.10 v2027.1.1].map { Releases::Version.parse(_1) }
    assert_equal %w[2026.9.3 2026.10.2 2026.10.10 2027.1.1], versions.sort.map(&:to_s)
  end

  test "the next version counts on within the month, and starts at 1 in a new one" do
    released = %w[v2026.10.1 v2026.10.2 v2026.11.1].map { Releases::Version.parse(_1) }
    assert_equal "2026.11.2", Releases::Version.following(released, on: Date.new(2026, 11, 20)).to_s
    assert_equal "2026.12.1", Releases::Version.following(released, on: Date.new(2026, 12, 1)).to_s
    assert_equal "2026.11.1", Releases::Version.following([], on: Date.new(2026, 11, 20)).to_s
  end
end
