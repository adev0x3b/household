# frozen_string_literal: true

# The assistant's tools. A subclass implements #execute with real keyword
# arguments, so RubyLLM refuses unknown or missing ones before any code runs.
# Every tool acts as the chat's profile and answers in one shape, ok with
# data or not ok with an error, which the instructions tell the model to
# trust. "Not found" and "not authorized" read the same, so the model can't
# probe the ids of other people's records.
#
# A tool lives for one turn, so it remembers what failed: the same call
# again isn't run, and a second failure of the same kind ends with "stop"
# and a note to tell the user, which ReplyJob doesn't push the model past.
module Assistant
  class Tool < RubyLLM::Tool
    def self.tool_name = name.demodulize.underscore.delete_suffix("_tool")

    # The key of the line the chat shows for a call (assistant.activity.*):
    # a read has its own words, a change (ChangeTool) one line for all.
    def self.activity_key = tool_name

    attr_reader :chat, :profile

    def initialize(chat:)
      super()
      @chat = chat
      @profile = chat.profile
    end

    # Instrumented as "tool_call.assistant", which the log and the eval
    # runner read.
    def call(tool_call: nil, **arguments)
      ActiveSupport::Notifications.instrument("tool_call.assistant", chat_id: chat.id, tool: name, arguments: arguments) do |event|
        result = repeated_call(arguments) || remember_failure(arguments, wrap { super })
        event.merge!(ok: result[:ok], error: result[:error], result: result)
        Assistant::Broadcaster.tool_activity(chat, name, arguments, result)
        result
      end
    end

    # A call that doesn't fit the schema is the model's mistake, not something
    # the user has to supply: the details are already in the chat.
    SHAPE_PROBLEM = /\AInvalid tool arguments/

    private

    def failures = @failures ||= {}

    def repeated_call(arguments)
      problem = failures[arguments]
      { ok: false, error: stop_note(problem), stop: true } if problem
    end

    def remember_failure(arguments, result)
      problem = failure_of(result)
      return result unless problem

      again = failures.value?(problem)
      failures[arguments] = problem
      return result unless again

      stop = stop_note(problem)
      result[:ok] ? result.merge(data: result[:data].merge(next: stop), stop: true) : result.merge(error: stop, stop: true)
    end

    def stop_note(problem)
      note = problem.to_s.match?(SHAPE_PROBLEM) ? :repeated_schema_mismatch : :repeated_failure
      Notes.render(note, tool: name, problem: problem)
    end

    # What went wrong, comparable between calls: the error, or what a change
    # still needs.
    def failure_of(result)
      return result[:error] unless result[:ok]

      data = result[:data]
      return unless data.is_a?(Hash) && data[:status] == "needs_input"

      Array(data[:changes]).flat_map { |change| [ *change[:problems], *Array(change[:missing]).map { |m| "missing #{m}" } ] }
        .presence&.uniq&.join("; ") || "still needs input"
    end

    def wrap
      value = yield
      if value.is_a?(Hash) && value.keys == [ :error ]
        error = value[:error].to_s
        return { ok: false, error: error.match?(SHAPE_PROBLEM) ? "#{error} — #{Notes.render(:schema_mismatch)}" : error }
      end

      { ok: true, data: value }
    rescue Failure, ArgumentError => e
      { ok: false, error: e.message }
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      { ok: false, error: "not found — look it up with search_records to get its id" }
    rescue Pundit::NotDefinedError
      { ok: false, error: "the assistant can't do that to this kind of record" }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error: e.record.errors.full_messages.to_sentence.presence || e.message }
    rescue StandardError => e
      # A bug in one tool shouldn't end the whole reply, so it is reported
      # and the model is told.
      Rails.error.report(e, handled: true, context: { tool: name, chat_id: chat.id })
      { ok: false, error: "internal error in #{name} (#{e.class}); nothing was changed by this call. Tell the user it didn't work." }
    end

    def fail!(message) = raise(Failure, message)

    def resource(type) = Resources.fetch(type)

    # An ISO date or the user's own words ("a week ago", "last Friday").
    def date(value, field)
      return if value.blank?

      parsed = DateWords.parse(value)
      fail!("#{field} must be YYYY-MM-DD or words like \"yesterday\" / \"a week ago\"") unless parsed

      parsed
    end

    # A time of the day as its code (Events::TimesOfDay), from "HH:MM" or a
    # word such as "dinner".
    def time_code(time)
      code = Events::TimesOfDay.code_for(time)
      fail!("can't read the time #{time.inspect} — give HH:MM, or breakfast / lunch / dinner / bedtime") unless code

      code
    end

    # An existing record by id, or a day of a series by its event and date,
    # saved or not. time picks one dose of a day, for a medication taken
    # several times a day.
    def locate(type, id: nil, event_id: nil, date: nil, time: nil)
      res = resource(type)
      return res.find_accessible(profile, id) if id.present?

      fail!("give an id, or an event_id and date for an upcoming occurrence") unless res.eventable? && event_id.present? && date.present?

      event = Event.accessible_by(profile).of_type(res.type).find(event_id)
      on = self.date(date, "date")
      code = time_code(time) if time.present?
      fail!("#{on} is not an occurrence of that series") unless event.occurrences.exists?(date: on) || event.occurrence_dates_between(on, on).include?(on)
      event.occurrence_for(on, time: code && event.timed? ? Events::TimesOfDay.hhmm(code) : nil)
    end

    def summarize(record) = Resources.for_record(record).summarize(record, profile: profile)
  end
end
