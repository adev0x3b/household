# frozen_string_literal: true

require "io/console"

module Provision
  # The questions: each with its default shown and taken on a bare Enter,
  # a yes/no, a choice among a few words, a secret typed unseen. With
  # --yes every default is taken without asking, and only what has none is
  # asked.
  class Prompt
    def initialize(input: $stdin, output: $stdout, assume_defaults: false)
      @input = input
      @output = output
      @assume_defaults = assume_defaults
    end

    def say(line) = @output.puts(line)

    def ask(question, default: nil, required: false)
      return default if @assume_defaults && !(required && blank?(default))

      loop do
        @output.print("#{question}#{" [#{default}]" unless blank?(default)}: ")
        answer = read_line
        answer = default.to_s if answer.empty?
        return answer unless required && answer.empty?

        @output.puts("Something is needed here.")
      end
    end

    def yes?(question, default: true)
      return default if @assume_defaults

      @output.print("#{question} [#{default ? "Y/n" : "y/N"}]: ")
      answer = read_line.downcase
      answer.empty? ? default : answer.start_with?("y")
    end

    # One of the options, named or picked by number.
    def choose(question, options, default:)
      return default if @assume_defaults

      loop do
        @output.puts(question)
        options.each_with_index { |option, index| @output.puts("  #{index + 1}. #{option}#{" (default)" if option == default}") }
        @output.print("> ")
        answer = read_line
        return default if answer.empty?
        return options[answer.to_i - 1] if answer.match?(/\A\d+\z/) && options[answer.to_i - 1]
        return answer if options.include?(answer)

        @output.puts("One of #{options.join(", ")}, please.")
      end
    end

    # Typed unseen; empty keeps what there was (the default), shown as its last four characters.
    def secret(question, default: nil, required: false)
      return default if @assume_defaults && !(required && blank?(default))

      hint = blank?(default) ? "" : " [kept, ends in #{default.to_s[-4..]}]"
      @output.print("#{question}#{hint}: ")
      answer = @input.respond_to?(:noecho) ? @input.noecho { read_line } : read_line
      @output.puts
      answer = default.to_s if answer.empty?
      return answer unless required && answer.empty?

      @output.puts("Something is needed here.")
      secret(question, default: default, required: required)
    end

    private

    def read_line
      line = @input.gets or raise EOFError, "no more input"
      line.chomp.strip
    end

    def blank?(value) = value.nil? || value.to_s.empty?
  end
end
