# frozen_string_literal: true

# A limit the environment named used to decide over the saved settings, and
# the settings page showed it locked. Now the saved row decides and the
# environment only gives a new row its starting values, so a copy whose
# environment names a limit has its value copied onto the row it already
# has, and behaves as it did until the admin changes it.
class KeepTheEnvironmentsLimitsOnTheSavedSettings < ActiveRecord::Migration[8.1]
  # The table as it is now, without the model's encryption and callbacks.
  class Setting < ActiveRecord::Base
    self.table_name = "platform_settings"
  end

  def up
    named = Platform::LIMITS.values.select { ENV[_1.env].present? }
    return if named.empty?

    Setting.update_all(named.to_h { [ _1.name, _1.starting_value ] })
  end

  # The values stay: they are what the row would have been read as.
  def down; end
end
