# frozen_string_literal: true

module Lexicon
  # Runs Lexicon::Import for the admin page (Lexicon::StartImport),
  # on the import record the page already shows — its steps fill in as the
  # job goes. Never retried: a failed import is a report to read, not an
  # error to repeat (the next Import press starts a fresh one).
  class ImportJob < ApplicationJob
    queue_as :default
    runs_once
    runs_outside_web_server

    # Cancelled: they stopped it themselves. Still running: it crashed before it could say.
    OUTCOMES = { "active" => :import_finished, "failed" => :import_failed,
                 "awaiting_review" => :import_needs_review, "unchanged" => :import_unchanged }.freeze

    # Every step runs (force): the page's Import is how an import is checked again.
    # download: false reads the file an earlier download kept.
    # resume: an import awaiting review goes on from its dictionary step (Continue).
    # notify: the profile to tell how it ended (whoever pressed the button).
    def perform(import_id, download: true, resume: false, notify: nil)
      import = LexiconImport.find(import_id)
      return if import.cancelled? # cancelled while it waited in the queue
      return if resume && !import.awaiting_review? # Continue pressed twice: the first job has it

      begin
        Lexicon::Import.call(import.language, import: import, download: download, force: true, resume: resume)
      ensure
        notify_outcome(import.reload, notify)
      end
    end

    private

    def notify_outcome(import, profile_id)
      kind = OUTCOMES[import.status]
      return if kind.nil?

      notify(profile_id, kind, subject: import, language: LexiconLanguage.name_of(import.language),
                               detail: (import.error if import.failed?))
    end
  end
end
