# frozen_string_literal: true

require "test_helper"

class SetupCodeTest < ActiveSupport::TestCase
  test "a code is sixteen characters a person can't misread, in groups of four" do
    codes = Array.new(50) { SetupCode.generate }

    codes.each { |code| assert_match(/\A([A-HJ-NP-Z2-9]{4}-){3}[A-HJ-NP-Z2-9]{4}\z/, code) }
    assert_equal codes.size, codes.uniq.size
  end

  # The installer makes codes with its own tools, so the digest is written
  # down here: SHA-256, in hex, of the sixteen characters alone.
  test "the digest is of the characters alone, whatever their case and spacing" do
    expected = Digest::SHA256.hexdigest("K7QM2XRD9VWPHC4T")

    assert_equal expected, SetupCode.digest("K7QM-2XRD-9VWP-HC4T")
    assert SetupCode.accepts?(" k7qm 2xrd\t9vwp-hc4t ", expected)
  end

  test "nothing is accepted without a code or a digest" do
    refute SetupCode.accepts?("", SetupCode.digest(""))
    refute SetupCode.accepts?("K7QM-2XRD-9VWP-HC4T", nil)
    refute SetupCode.accepts?("K7QM-2XRD-9VWP-HC4X", SetupCode.digest("K7QM-2XRD-9VWP-HC4T"))
  end
end
