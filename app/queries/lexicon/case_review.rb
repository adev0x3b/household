# frozen_string_literal: true

module Lexicon
  # Which of a language's eval cases count — confirmed by a person, and not
  # the same word as an earlier one (their households would hold two supplies
  # of one name) — and why each of the others waits, as a hint for whoever
  # reviews them:
  #   :unconfirmed        looks right — confirm it
  #   :not_in_dictionary  not a word of the language ("gause", "strips" left in English)
  #   :unlinked           the dictionary doesn't say it means the concept ("agli" for needle)
  #   :duplicate          a confirmed case already has this word
  # imports: the imports the language is read with (the candidate one during
  # an import), read ahead for every case.
  #
  #   review = Lexicon::CaseReview.new(cases, language, imports)
  #   review.counted  # => [LexiconEvalCase, …]
  #   review.waiting  # => [[LexiconEvalCase, :unlinked], …]
  class CaseReview
    def initialize(cases, language, imports)
      @cases = cases
      @language = language
      @imports = imports
    end

    def counted = sorted.first
    def waiting = sorted.last

    private

    def sorted
      @sorted ||= begin
        matcher = Matcher.new(imports: @imports).prefetch(@cases.flat_map { [ _1.native_plural, EvalCases.english_plural(_1) ] })
        counted = []
        waiting = []
        @cases.each do |kase|
          reason = if !kase.confirmed? then hint(kase, matcher) || :unconfirmed
          elsif counted.any? { Text.fold(_1.native_plural) == Text.fold(kase.native_plural) } then :duplicate
          end
          reason ? waiting << [ kase, reason ] : counted << kase
        end
        [ counted, waiting ]
      end
    end

    # What looks wrong in a case the model wrote, or nil.
    def hint(kase, matcher)
      return :not_in_dictionary unless in_dictionary?(kase, matcher)

      :unlinked unless matcher.link(kase.native_plural, EvalCases.english_plural(kase))
    end

    # Whether the case's word is one the language's dictionary knows, as a
    # whole or by its head word.
    def in_dictionary?(kase, matcher)
      words = Text.words(kase.native_plural)
      keys = [ words.join(" "), (@language.head == "first" ? words.first : words.last) ].compact.uniq
      keys.any? { matcher.listed?(@language.code, _1) }
    end
  end
end
