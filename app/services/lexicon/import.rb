# frozen_string_literal: true

# Imports one language's nouns from its kaikki.org extract and activates
# them only if they pass its checks; docs/architecture/assistant.md, "The
# lexicon", lists the steps. Its parts have inputs of their own: Report
# writes each step to the record, Loader is the streaming pass, and the
# judging steps here hand Verification, DictionaryCheck and AgentEval what
# they need and keep what they answer.
module Lexicon
  class Import
    STEPS = %w[configure source download parse load verify dictionary agent activate].freeze
    RESUMED_AT = "dictionary"
    STREAM_STEPS = %w[download parse load].freeze
    UNFINISHED = %w[pending running].freeze
    SHRINK_GUARD = 0.8

    class Cancelled < StandardError; end

    class StepFailed < StandardError
      attr_reader :step

      def initialize(step, message)
        super(message)
        @step = step
      end
    end

    def self.call(language, **options) = new(language, **options).call

    # Every step pending: what a new import shows before it starts.
    def self.initial_report = { "steps" => STEPS.map { { "name" => _1, "status" => "pending" } }, "checks" => [], "counts" => {} }

    def self.size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: :en)

    # language: a code from config/lexicons.yml, or a Config::Language.
    # source: a local .jsonl.gz instead of the language's URL.
    # download: false reads the file an earlier download kept (Lexicon::Downloads).
    # force: import even when the extract is unchanged since the active import
    # (the admin page always does: every step runs again).
    # import: a LexiconImport already created (the admin page's job).
    # agent: :skip activates without the agent step (recorded as skipped);
    # a callable(import, language, on_progress) stands in for Lexicon::AgentEval (tests).
    # resume: an import awaiting review goes on from the dictionary step.
    def initialize(language, source: nil, download: true, force: false, import: nil, on_step: nil, agent: nil, resume: false)
      @language = language.is_a?(Config::Language) ? language : nil
      @code = (@language&.code || language).to_s
      @source_path = source.presence
      @download = download
      @force = force
      @import = import
      @on_step = on_step
      @agent = agent
      @resume = resume
      @counts = Hash.new(0)
      # Raised here, before call's rescue would record it as the import failing.
      raise ArgumentError, "only an import awaiting review resumes (#{import&.status || "none given"})" if resume && !import&.awaiting_review?
    end

    def call
      return resume if @resume

      @import = start_import
      @report = Report.new(@import, counts: @counts, on_step: @on_step)
      @report.run("configure") { configure }
      @report.run("source") { check_source }
      return finish_unchanged if @unchanged

      Loader.new(@import, @language, @source, @report, counts: @counts).load
      @report.run("verify") { verify }
      finish
    rescue StepFailed => e
      fail_import(e.step, e.message)
    rescue Cancelled
      cancel_import
    rescue StandardError => e
      crashed(e)
    end

    private

    # The steps that judge the import, then activation — or a wait for review.
    def finish
      return await_review if check_dictionary == :awaiting

      evaluate_agent
      @report.run("activate") { activate }
      @import
    end

    def resume
      @language ||= Config.fetch(@import.language)
      @counts.merge!(@import.counts)
      @import.update!(status: :running, finished_at: nil)
      @report = Report.new(@import, counts: @counts, on_step: @on_step)
      STEPS.drop(STEPS.index(RESUMED_AT)).each { @report.mark(_1, "pending") }
      finish
    rescue StepFailed => e
      fail_import(e.step, e.message)
    rescue Cancelled
      cancel_import
    rescue StandardError => e
      crashed(e)
    end

    # A bug, not bad data: still recorded where it happened, never left "running".
    def crashed(error)
      raise error unless @import&.persisted?

      @report ||= Report.new(@import, counts: @counts, on_step: @on_step)
      Rails.error.report(error, handled: true, context: { language: @code, step: @report.current })
      fail_import(@report.current || "configure", "unexpected #{error.class.name}: #{error.message.truncate(300)}")
    end

    def start_import
      attributes = { language: @code, status: :running, started_at: Time.current, finished_at: nil, failed_step: nil, error: nil,
                     report: self.class.initial_report }
      @import ? @import.tap { _1.update!(attributes) } : LexiconImport.create!(attributes)
    end

    def configure
      @language ||= begin
        Config.fetch(@code)
      rescue Config::Unknown => e
        raise StepFailed.new("configure", e.message)
      end
      problems = @language.problems
      raise StepFailed.new("configure", "#{@code}: #{problems.join("; ")}") if problems.any?

      running = LexiconImport.running.where(language: @code).where.not(id: @import.id).latest_first.find(&:live?)
      raise StepFailed.new("configure", "another import of #{@code} is running (##{running.id})") if running

      "#{@language.wiktionary}#{" (pivot)" if @language.pivot?}, #{@language.checks.size} checks"
    end

    def check_source
      @source = source
      head = @source.head
      @import.update!(source_url: @source.label, source_etag: head[:etag], source_last_modified: head[:last_modified])
      active = LexiconImport.active_for(@code)
      @unchanged = !@force && active && head[:etag].present? && active.source_etag == head[:etag]
      detail = [ (head[:size] && self.class.size(head[:size])), (head[:last_modified] && "updated #{head[:last_modified].to_date}") ]
      detail << "unchanged since the active import — FORCE=1 imports it anyway" if @unchanged
      detail.compact.join(", ")
    rescue Source::Error => e
      raise StepFailed.new("source", "#{e.message} (#{@source&.label || @language.url})")
    end

    def source
      return Source.new(path: @source_path) if @source_path
      return Source.new(url: @language.url, store_to: Downloads.path(@code)) if @download

      kept = Downloads.path(@code)
      raise StepFailed.new("source", "no file of #{@code} has been downloaded yet — import it with a new download") unless kept.file?

      Source.new(path: kept)
    end

    # ── Judging: the data checks, the dictionary (no model), the assistant against English alone ──

    def verify
      lemmas = @counts["lemmas"]
      @import.update!(lemma_count: lemmas)
      if lemmas < @language.min_lemmas
        raise StepFailed.new("verify", "only #{lemmas} nouns, fewer than min_lemmas (#{@language.min_lemmas}) — a broken or partial extract")
      end

      active = LexiconImport.active_for(@code)
      if active && lemmas < active.lemma_count * SHRINK_GUARD
        raise StepFailed.new("verify", "#{lemmas} nouns, under #{(SHRINK_GUARD * 100).round}% of the active import's #{active.lemma_count} — kept the active one")
      end

      results = Verification.new(@import, @language).run
      @report.keep("checks", results.map(&:to_h))
      failed = results.reject(&:ok)
      if failed.any?
        raise StepFailed.new("verify", "#{failed.size} of #{results.size} checks failed: " +
                                       failed.map { |r| "#{r.check} (got #{r.got})" }.join("; "))
      end

      "#{lemmas} nouns, all #{results.size} checks passed"
    end

    # :awaiting when the language's test cases need a person first.
    def check_dictionary
      @report.run("dictionary") do
        draft_cases
        summary = DictionaryCheck.new(@import, @language).run
        next Report::Skip.new("no translated language with confirmed test cases to check the pivot against") unless summary

        @report.keep("dictionary", summary.to_h)
        raise StepFailed.new("dictionary", summary.problem) unless summary.pass?

        summary.detail
      end
    rescue DictionaryCheck::NeedsReview => e
      await(e.message)
    rescue EvalCases::Error => e
      await("the model couldn't write the test cases (#{e.message}) — write them again on the page, confirm them, then Continue")
    end

    def await(message)
      @awaiting = message
      :awaiting
    end

    # A translated language with no test cases yet has the model draft them
    # here, once, for a person to confirm on the page; the check then finds
    # none confirmed and the import waits.
    def draft_cases
      return if @language.pivot?

      record = LexiconLanguage.find_by!(code: @language.code)
      EvalCases.generate!(record) unless record.lexicon_eval_cases.exists?
    end

    def evaluate_agent
      return @report.mark("agent", "skipped", "skipped by AGENT=skip — activated without testing it against the agent") if @agent == :skip

      @report.run("agent") do
        summary = agent_runner.call(@import, @language, ->(text) { @report.progress("agent" => text) })
        next Report::Skip.new("no translated language to test the pivot against") unless summary

        @report.keep("agent", summary.to_h.merge("status" => summary.pass? ? "passed" : "failed"))
        raise StepFailed.new("agent", summary.problem) unless summary.pass?

        summary.detail
      end
    rescue AgentEval::Cancelled
      raise Cancelled
    rescue AgentEval::Failure => e
      raise StepFailed.new("agent", e.message)
    end

    def agent_runner
      @agent || lambda do |import, language, on_progress|
        AgentEval.new(import, language, on_progress: on_progress, cancelled: -> { import.cancel_requested? }).run
      end
    end

    def activate
      previous = LexiconImport.where(language: @import.language, status: %i[active awaiting_review]).where.not(id: @import.id).to_a
      LexiconImport.transaction do
        previous.each { _1.update!(status: :superseded) }
        @import.update!(status: :active, finished_at: Time.current)
      end
      previous.each { |old| LexiconLemma.where(lexicon_import_id: old.id).delete_all }
      previous.any? ? "replaced import ##{previous.map(&:id).join(", #")}" : "first import of #{@import.language}"
    end

    # ── How an import ends when it isn't activated ──

    def await_review
      @report.mark("dictionary", "waiting", @awaiting)
      @import.update!(status: :awaiting_review, finished_at: Time.current, lemma_count: @counts["lemmas"].nonzero? || @import.lemma_count)
      @import
    end

    # Stopped on request: the step it was in says so, the rest is skipped, its rows go.
    def cancel_import
      step = @report.current || "configure"
      @report.mark(step, "cancelled", "cancelled on request")
      STEPS.each { |name| @report.mark(name, "skipped") if UNFINISHED.include?(@report.status_of(name)) }
      LexiconLemma.where(lexicon_import_id: @import.id).delete_all
      @import.update!(status: :cancelled, failed_step: step, error: "cancelled on request", finished_at: Time.current)
      @import
    end

    def finish_unchanged
      (STEPS - %w[configure source]).each { @report.mark(_1, "skipped") }
      @import.update!(status: :unchanged, finished_at: Time.current)
      @import
    end

    def fail_import(step, message)
      @report.mark(step, "failed", message)
      STEPS.drop(STEPS.index(step) + 1).each { @report.mark(_1, "skipped") }
      # The stream's steps that did finish before a later one failed stay ok.
      (STREAM_STEPS - [ step ]).each { |name| @report.mark(name, "skipped") if @report.status_of(name) == "running" }
      LexiconLemma.where(lexicon_import_id: @import.id).delete_all
      @import.update!(status: :failed, failed_step: step, error: message, finished_at: Time.current)
      @import
    end
  end
end
