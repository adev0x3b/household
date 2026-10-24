# frozen_string_literal: true

# Something a copy lets its people do or not (Platform): on unless the admin
# turned it off. Until the settings are first saved, the environment may
# start it off; that is how the public demo begins with uploads off.
class Platform::Switch
  # What turns a switch off in the environment; anything else, or nothing, leaves it on.
  OFF = %w[off false no 0].freeze

  attr_reader :name, :env

  def initialize(name, env:)
    @name = name
    @env = env
  end

  # What a new row of settings takes (Platform.starting_values).
  def starting_value = !OFF.include?(ENV[@env].to_s.strip.downcase)

  # saved: the Platform::Setting row, or nil before there is one.
  def value(saved)
    return starting_value if saved.nil?

    saved.public_send(@name) != false
  end
end
