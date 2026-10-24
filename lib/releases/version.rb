# frozen_string_literal: true

module Releases
  # A calendar version: the year, the month and the release's number within
  # that month. The month isn't padded, so the version is also a valid
  # semantic version, and tools that expect one order it correctly.
  class Version < Data.define(:year, :month, :number)
    include Comparable

    TAG = /\Av(\d{4})\.([1-9]|1[0-2])\.([1-9]\d*)\z/

    # The version a tag names, or nil for a tag that isn't a release's.
    def self.parse(tag)
      match = TAG.match(tag.to_s) or return

      new(*match.captures.map(&:to_i))
    end

    # The version of a release made on `date`, after those already made.
    def self.following(released, on:)
      numbers = released.select { _1.year == on.year && _1.month == on.month }.map(&:number)
      new(on.year, on.month, numbers.max.to_i + 1)
    end

    def <=>(other) = parts <=> other.parts
    def parts = [ year, month, number ]
    def to_s = parts.join(".")
    def tag = "v#{self}"
  end
end
