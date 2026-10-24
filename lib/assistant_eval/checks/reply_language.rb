# frozen_string_literal: true

module AssistantEval
  module Checks
    # A reply is taken to be in the language most of its little words belong
    # to; one too short to tell is let through.
    class ReplyLanguage < Turns
      LANGUAGE_WORDS = {
        "en" => %w[the and is are you your have has been it for with to of was this that will can been your],
        "it" => %w[il la le gli lo di che è sono stato stata hai ho per con una un del della tuo tua questo questa è]
      }.freeze

      def self.key = "reply_language"
      def self.argument = "Language code the assistant's replies must be in (en, it)"
      def self.example = "it"

      def call(code)
        wrong = model_turns.filter_map do |turn, number|
          words = said(turn).downcase.scan(/[[:alpha:]]+/)
          next if words.size < 5

          scores = LANGUAGE_WORDS.transform_values { |list| words.count { |word| list.include?(word) } }
          guess, score = scores.max_by { |_, count| count }
          "turn #{number} reads as #{guess}" if score.positive? && guess != code.to_s && score > scores[code.to_s].to_i
        end
        "reply_language: expected #{code}, #{wrong.join(", ")}" if wrong.any?
      end
    end
  end
end
