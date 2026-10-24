# frozen_string_literal: true

class Assistant::ReplyJob
  # What went wrong in a turn that raised, sorted by who can do something
  # about it: the reason the person reads (Assistant::ReplyFailure), and
  # what is reported for whoever runs the app. A provider that is down
  # waits for a moment, a copy set up wrong waits for its admin, and
  # anything not listed here is a bug.
  #
  #   trouble = Trouble.of(error)
  #   Rails.error.report(trouble.reported(error), handled: true, severity: trouble.severity)
  #   trouble.reason   # => :setup
  class Trouble
    # Reported in place of the provider's error, which is kept as their
    # cause: one class per thing the admin would do, and a message that
    # says what, the same every time, so a problem is one entry on
    # /admin/errors however often it happens.
    class ModelUnreachable < StandardError; end
    class ModelRateLimited < StandardError; end
    class ModelKeyRefused < StandardError; end
    class ModelUnpaid < StandardError; end
    class ModelMissing < StandardError; end
    class ContextOverflow < StandardError; end

    # Ollama answers 404 for a model it hasn't pulled, which RubyLLM raises
    # as its plain Error.
    MODEL_NOT_FOUND = ->(error) { error.is_a?(RubyLLM::Error) && error.response&.status == 404 }

    attr_reader :reason, :severity

    # errors: the classes (or a matcher) this trouble covers; reported: the
    # class reported for it and its message, none for a bug, which is
    # reported as it is.
    def initialize(errors:, reason:, severity:, reported: nil, advice: nil)
      @errors = errors
      @reason = reason
      @severity = severity
      @reported = reported
      @advice = advice
    end

    def covers?(error) = @errors.any? { |matcher| matcher === error }

    def reported(error)
      return error unless @reported

      raise @reported, @advice, cause: error
    rescue @reported => reported
      reported
    end

    ALL = [
      new(errors: [ Faraday::ConnectionFailed, Faraday::TimeoutError, RubyLLM::ServerError, RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError ],
          reason: :unreachable, severity: :warning, reported: ModelUnreachable,
          advice: "The model's server isn't answering: check that it is running and that the app can reach it."),
      new(errors: [ RubyLLM::RateLimitError ],
          reason: :rate_limited, severity: :warning, reported: ModelRateLimited,
          advice: "The model's provider is turning requests away for now: check the account's rate limits."),
      new(errors: [ RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError, RubyLLM::ConfigurationError ],
          reason: :setup, severity: :error, reported: ModelKeyRefused,
          advice: "The model's provider refused the API key, or none is set: check it on the assistant's settings."),
      new(errors: [ RubyLLM::PaymentRequiredError ],
          reason: :setup, severity: :error, reported: ModelUnpaid,
          advice: "The model's provider wants paying before it answers: check the account's credit."),
      new(errors: [ RubyLLM::ModelNotFoundError, MODEL_NOT_FOUND ],
          reason: :setup, severity: :error, reported: ModelMissing,
          advice: "The model isn't on its server: pull it there, or pick another on the assistant's settings."),
      new(errors: [ RubyLLM::ContextLengthExceededError ],
          reason: :context_full, severity: :error, reported: ContextOverflow,
          advice: "A conversation outgrew the model's context window, which compaction should prevent: check the window set on the assistant's settings.")
    ].freeze

    BUG = new(errors: [ StandardError ], reason: :failed, severity: :error)

    def self.of(error) = ALL.find { |trouble| trouble.covers?(error) } || BUG
  end
end
