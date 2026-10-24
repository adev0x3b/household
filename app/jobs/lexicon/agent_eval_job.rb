# frozen_string_literal: true

module Lexicon
  # Runs an active import's agent evals again (Lexicon::AgentEval) — after a
  # model change, or edited cases — for the admin page. A report, never a
  # gate: the import stays active whatever the result. The result replaces
  # report["agent"], marked as a re-run.
  class AgentEvalJob < ApplicationJob
    queue_as :default
    runs_once
    runs_outside_web_server

    # by: the profile to tell how it ended.
    def self.start(import, by: nil)
      import.report["agent"] = { "status" => "running", "rerun" => true, "detail" => "starting" }
      import.update_columns(report: import.report, updated_at: Time.current)
      perform_later(import.id, notify: by&.id)
    end

    def perform(import_id, notify: nil)
      @notify = notify
      import = LexiconImport.find(import_id)
      language = Lexicon::Config.fetch(import.language)
      progress = ->(text) { save(import, { "status" => "running", "rerun" => true, "detail" => text }) }
      summary = Lexicon::AgentEval.new(import, language, on_progress: progress).run
      result = summary ? summary.to_h.merge("status" => summary.pass? ? "passed" : "failed") : { "status" => "skipped", "detail" => "nothing to test with" }
      save(import, result.merge("rerun" => true))
      tell(import, result)
    rescue Lexicon::AgentEval::Failure => e
      save(import, { "status" => "failed", "rerun" => true, "detail" => e.message })
      tell(import, { "status" => "failed", "detail" => e.message })
    end

    private

    def tell(import, result)
      notify(@notify, result["status"] == "passed" ? :lexicon_eval_passed : :lexicon_eval_failed, subject: import,
                                                                                                  language: LexiconLanguage.name_of(import.language), detail: result["detail"])
    end

    def save(import, agent)
      import.report["agent"] = agent
      import.update_columns(report: import.report, updated_at: Time.current)
    end
  end
end
