# frozen_string_literal: true

# A language's checks (config/lexicons.yml) run against one import — a new
# one before it's activated, or the active one (lexicon:verify):
#
#   Lexicon::Verification.new(import, language).run
#   # => [#<Result check="form: aghi · lemma: ago" ok=true got="ago">, …]
#
# Each check is one of Lexicon::Checks, found by its kind.
module Lexicon
  class Verification
    Result = Data.define(:check, :ok, :got) do
      def to_h = { "check" => check, "ok" => ok, "got" => got }
    end

    def initialize(import, language)
      @import = import
      @language = language
    end

    def run = @language.checks.map { |check| result(check) }

    private

    def result(check)
      ok, got = Checks.named(check.kind).new(@import, @language, check.spec).call
      Result.new(check: check.to_s, ok: ok, got: got.presence || "nothing")
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { check: check.to_s })
      Result.new(check: check.to_s, ok: false, got: "error: #{e.message.truncate(120)}")
    end
  end
end
