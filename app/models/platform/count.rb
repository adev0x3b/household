# frozen_string_literal: true

# How many of something a household may have, or do in a day (Platform): no
# limit unless the admin set one, or a default where something must always
# have one (the mail the installation sends). Until the settings are first
# saved, the environment may start it at a number.
class Platform::Count
  attr_reader :name, :env, :minimum, :default

  # minimum: the least the admin may set. default: what an unset count
  # reads as; nil is no limit.
  def initialize(name, env:, minimum: 0, default: nil)
    @name = name
    @env = env
    @minimum = minimum
    @default = default
  end

  # What a new row of settings takes (Platform.starting_values): a whole
  # number the row can hold, else the default.
  def starting_value
    count = ENV[@env].to_s.strip[/\A\d+\z/]&.to_i
    count && count >= @minimum ? count : @default
  end

  # saved: the Platform::Setting row, or nil before there is one.
  def value(saved)
    return starting_value if saved.nil?

    saved.public_send(@name) || @default
  end
end
