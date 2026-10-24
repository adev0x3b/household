# frozen_string_literal: true

# Tells every admin, on their bell and their devices, about something
# only they can fix: a new kind of error, a job that failed for good.
#
#   Admins::Alert.call(:job_failed, name: "Uploads::FinishJob", detail: "Errno::ENOSPC: No space left on device")
#
# `kind` is a Notification kind and `name` what it is about, which its
# title quotes. The same kind about the same name rings once an hour at
# most, so a failure that repeats all night is one alert, not a phone that
# never stops.
module Admins
  class Alert
    EVERY = 1.hour

    def self.call(kind, name:, **data)
      return unless first_this_hour?(kind, name)

      AlertJob.perform_later(kind.to_s, { name: name, **data }.stringify_keys)
    rescue StandardError => e
      # Called while something else is failing, often from inside the error
      # reporter or a failing job: its own failure is reported, never raised
      # into theirs.
      Rails.error.report(e, handled: true, context: { alert: kind, name: name })
    end

    # Counted in the cache, which every process shares: a counter that
    # starts at one starts the hour.
    def self.first_this_hour?(kind, name)
      Rails.cache.increment("admins/alert/#{kind}/#{name}", 1, expires_in: EVERY) == 1
    end
    private_class_method :first_this_hour?
  end
end
