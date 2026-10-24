# frozen_string_literal: true

module AssistantEval
  # A scenario's `expect` list judged against what it left behind: each entry
  # is { check name => argument }, run by its AssistantEval::Checks class,
  # plus the checks every scenario gets unless it switches them off.
  class Expectations
    # turns: the scenario's AssistantEval::Runner::Turn list; nil when only the
    # data is checked (the null baseline, the oracle replays), and the checks
    # about the chat then hold.
    def initialize(profile, turns: nil)
      @records = Checks::Records.new(profile)
      @turns = turns
    end

    # => [] when everything holds, else the reasons.
    def failures(expect)
      named = expect.flat_map(&:keys)
      explicit = expect.flat_map { |entry| entry.map { |name, argument| outcome(name, argument) } }
      defaults = Checks.all.select(&:on_by_default?).reject { named.include?(_1.key) }.map { outcome(_1.key, true) }
      (explicit + defaults).compact
    end

    private

    # A check that breaks on its argument fails the scenario with the reason,
    # rather than stopping the whole run.
    def outcome(name, argument)
      check = Checks.named(name)
      return "#{name}: no such check" if check.nil?
      return if check.about_turns? && @turns.nil?

      check.new(@records, @turns).call(argument)
    rescue StandardError => e
      "#{name}: #{e.class}: #{e.message.truncate(120)}"
    end
  end
end
