# frozen_string_literal: true

module Provision
  # The path the app lives under, as the app reads it (config/application.rb):
  # a leading slash, no trailing one; empty for the domain's root, however it
  # was typed ("", "/", "love/", "/love/").
  module Mount
    def self.normalise(value)
      inner = value.to_s.strip.gsub(%r{\A/+|/+\z}, "")
      inner.empty? ? "" : "/#{inner}"
    end
  end
end
