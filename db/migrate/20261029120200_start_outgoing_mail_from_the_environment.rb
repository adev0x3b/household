# frozen_string_literal: true

# The mail switch and budgets are the saved row's once it exists, like every
# limit (Platform), but a copy's row was made before they were columns. A
# destination whose environment names them (staging, dev and the demo say
# OUTGOING_MAIL=off) gets them copied onto its row, and starts as its
# environment says rather than as the defaults do. Only these columns: the
# other limits are already the admin's.
class StartOutgoingMailFromTheEnvironment < ActiveRecord::Migration[8.1]
  # The table as it is now, without the model's encryption and callbacks.
  class Setting < ActiveRecord::Base
    self.table_name = "platform_settings"
  end

  # What turns the switch off, as Platform::Switch reads it today.
  OFF = %w[off false no 0].freeze
  # Each budget's variable and the least it may be.
  COUNTS = { mails_per_hour: [ "MAILS_PER_HOUR", 2 ], mails_per_day: [ "MAILS_PER_DAY", 6 ],
             reminder_mails_per_day: [ "REMINDER_MAILS_PER_DAY", 0 ] }.freeze

  def up
    values = counts
    values[:outgoing_mail] = !OFF.include?(ENV["OUTGOING_MAIL"].strip.downcase) if ENV["OUTGOING_MAIL"].present?
    Setting.update_all(values) if values.any?
  end

  # The values stay: they are what the row would have been read as.
  def down; end

  private

  def counts
    COUNTS.filter_map do |column, (name, minimum)|
      count = ENV[name].to_s.strip[/\A\d+\z/]&.to_i
      [ column, count ] if count && count >= minimum
    end.to_h
  end
end
