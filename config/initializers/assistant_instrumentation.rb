# frozen_string_literal: true

# One log line per assistant tool call (instrumented in Assistant::Tool#call):
#   [assistant] chat=7 save_draft 312ms ok
# grep the log for "[assistant]" to follow what the model did. What the call
# sent and got back carries the household's words (titles, notes, lab
# values), so it is logged only at debug level. The full record is in the
# chat's debug panel (?debug=1) and assistant:trace.
ActiveSupport::Notifications.subscribe("tool_call.assistant") do |event|
  payload = event.payload
  call = "[assistant] chat=#{payload[:chat_id]} #{payload[:tool]}"
  Rails.logger.info("#{call} #{event.duration.round}ms #{payload[:ok] ? "ok" : "FAILED"}")
  Rails.logger.debug { "#{call} args=#{Assistant::Trace.brief(payload[:arguments])} → #{Assistant::Trace.brief(payload[:result])}" }
end
