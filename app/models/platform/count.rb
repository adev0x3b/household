# frozen_string_literal: true

# How many of something a household may have, or do in a day (Platform): no
# limit unless the admin set one. Until the settings are first saved, the
# environment may start it at a number.
class Platform::Count
  attr_reader :name, :env

  # minimum: the least the admin may set; nil is still no limit.
  def initialize(name, env:, minimum: 0)
    @name = name
    @env = env
    @minimum = minimum
  end

  # What a new row of settings takes (Platform.starting_values): a whole
  # number the row can hold, else nil for no limit.
  def starting_value
    count = ENV[@env].to_s.strip[/\A\d+\z/]&.to_i
    count if count && count >= @minimum
  end

  # saved: the Platform::Setting row, or nil before there is one.
  def value(saved)
    return starting_value if saved.nil?

    saved.public_send(@name)
  end
end
