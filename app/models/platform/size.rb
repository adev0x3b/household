# frozen_string_literal: true

# How much a household may keep, in bytes (Platform): the default unless the
# admin set another. Until the settings are first saved, the environment may
# start it at another size ("50GB", "512 MB").
class Platform::Size
  UNITS = { "B" => 1, "KB" => 1.kilobyte, "MB" => 1.megabyte, "GB" => 1.gigabyte, "TB" => 1.terabyte }.freeze

  attr_reader :name, :env, :default

  def initialize(name, env:, default:)
    @name = name
    @env = env
    @default = default
  end

  # "50GB", "512 MB", "1024" (bytes); nil when it isn't one.
  def self.parse(text)
    match = text.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*([KMGT]?B)?\z/i)
    return if match.nil?

    (match[1].to_f * UNITS.fetch(match[2].to_s.upcase.presence || "B")).round
  end

  # What a new row of settings takes (Platform.starting_values): the
  # environment's size, else the default when there is none or it isn't one.
  def starting_value
    size = self.class.parse(ENV[@env])
    size&.positive? ? size : @default
  end

  # saved: the Platform::Setting row, or nil before there is one.
  def value(saved)
    return starting_value if saved.nil?

    saved.public_send(@name) || @default
  end
end
