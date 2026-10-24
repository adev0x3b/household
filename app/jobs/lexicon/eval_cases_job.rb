# frozen_string_literal: true

module Lexicon
  # Writes (or rewrites) a language's eval cases with the model, for the admin
  # page's "Write the test cases again" (Lexicon::EvalCases; edited cases are
  # kept). While it runs the language says so (cases_writing_since); a failure
  # is kept on it (cases_error) for the page.
  class EvalCasesJob < ApplicationJob
    queue_as :default
    runs_once
    runs_outside_web_server

    # A write older than this is a crashed job: the page stops saying it's running.
    STALE = 15.minutes

    def self.writing?(language) = language.cases_writing_since.present? && language.cases_writing_since > STALE.ago

    # by: the profile to tell how it ended.
    def self.start(language, by: nil)
      language.update!(cases_writing_since: Time.current, cases_error: nil)
      perform_later(language.id, notify: by&.id)
    end

    def perform(language_id, notify: nil)
      language = LexiconLanguage.find(language_id)
      Lexicon::EvalCases.generate!(language)
      language.update!(cases_writing_since: nil)
      notify(notify, :eval_cases_written, subject: language, language: language.wiktionary)
    rescue Lexicon::EvalCases::Error => e
      language.update!(cases_writing_since: nil, cases_error: e.message)
      notify(notify, :eval_cases_failed, subject: language, language: language.wiktionary, detail: e.message)
    end
  end
end
