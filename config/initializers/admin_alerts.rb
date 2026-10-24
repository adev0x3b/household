# frozen_string_literal: true

# The admin hears of an error the first time Solid Errors sees its kind,
# and again when one they marked resolved comes back; until then, more of
# the same only add occurrences on /admin/errors.
#
# What a job raises as it fails for good is reported by the job runner,
# and ApplicationJob has already told the admin about it as a failed
# job, so it isn't told twice.
ActiveSupport::Notifications.subscribe(/\Aerror_(created|reopened)\.solid_errors\z/) do |event|
  error = event.payload[:error]
  next if error.source.in?(%w[application.solid_queue application.active_job])

  Admins::Alert.call(:error_reported, name: error.exception_class, detail: error.message)
end
