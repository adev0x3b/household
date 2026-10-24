# frozen_string_literal: true

module Lexicon
  # An import started from the admin page: the record the page shows at
  # once, then its job. A language imports one at a time: while one is
  # really going, starting another is refused.
  class StartImport
    Result = ServiceResult.define(:import)

    # error: :already_running, or :not_queued when the job couldn't be
    # queued (the import has failed then, its error saying why).
    def self.call(language, by:, download: true)
      return Result.new(import: nil, error: :already_running) if LexiconImport.live_for(language.code)

      import = LexiconImport.create!(language: language.code, status: :running, started_at: Time.current, report: Import.initial_report)
      Result.new(import: import, error: (:not_queued unless import.enqueue!(download: download, notify: by.id)))
    end
  end
end
