# frozen_string_literal: true

# One eval run as saved by `assistant:eval` (tmp/assistant_evals/<id>.json).
# The task rewrites the file after every result, so a run in progress can
# be read too: running while its process lives, crashed if it died first.
# Files from before live progress (no "finished" key) count as finished.
module AssistantEval
  class RunFile
    ID_FORMAT = /\A[\w.-]+\z/

    def self.dir = @dir || Rails.root.join("tmp/assistant_evals")

    # Tests point this at a temporary directory.
    def self.dir=(path)
      @dir = path && Pathname(path)
    end

    def self.recent(limit = 20)
      Dir[dir.join("*.json")].reverse.first(limit).filter_map { |path| read(path) }
    end

    def self.find(id)
      path = dir.join("#{id}.json")
      id.to_s.match?(ID_FORMAT) && path.exist? ? read(path) : nil
    end

    def self.running = recent(5).find(&:running?)

    # One page of runs, newest first (will_paginate): only that page's files
    # are read, since a run's file holds every transcript.
    def self.paginate(page:, per_page:)
      paths = Dir[dir.join("*.json")].reverse
      page = page.to_i.clamp(1, [ (paths.size.to_f / per_page).ceil, 1 ].max)
      WillPaginate::Collection.create(page, per_page, paths.size) do |pager|
        pager.replace(Array(paths[pager.offset, pager.per_page]).filter_map { |path| read(path) })
      end
    end

    def self.read(path)
      new(File.basename(path, ".json"), JSON.parse(File.read(path)))
    rescue JSON::ParserError
      nil # caught mid-write by an older task version; the next poll reads it
    end

    attr_reader :id, :data

    def initialize(id, data)
      @id = id
      @data = data
    end

    def model = data["model"]
    def provider = data["provider"]
    def runs = data["runs"]
    def pid = data["pid"]
    def draft? = data["draft"].present?
    def started_at = data["started_at"] && Time.zone.parse(data["started_at"])
    def results = data.fetch("results", [])
    def total = data["total"] || results.size
    def done = results.size
    def passed = results.count { |r| self.class.status(r) == "passed" }
    # Errors are the plumbing (unreachable model, crashed harness): not scored.
    def errors = results.count { |r| self.class.status(r) == "error" }
    def scored = done - errors
    def finished? = !data.key?("finished") || data["finished"]

    # More than this share of a run unscored (the model server went away
    # mid-run) and its pass rate says little: shown, but flagged, and never
    # the overview's headline.
    UNRELIABLE_SHARE = 0.2

    def unreliable? = done.positive? && errors.fdiv(done) > UNRELIABLE_SHARE

    # Seconds the task spent waiting for the model server to come back.
    def paused_for = data["paused_for"].to_i

    # The task gave up waiting for the model server and finished early.
    def gave_up? = data["gave_up"] == true

    # Scenarios that passed some repetitions and failed others: unstable,
    # which "3/5" alone doesn't say.
    def flaky_scenarios = pass_counts.select { |_, (passed, scored, _)| passed.positive? && passed < scored }.keys

    # When the task last wrote the file: after the last result, so for a
    # finished run, when it ended.
    def updated_at
      path = self.class.dir.join("#{id}.json")
      path.exist? ? path.mtime : nil
    end

    # passed / failed / error; older files have no status (an error meant a crash).
    def self.status(result) = result["status"] || (result["error"] ? "error" : (result["passed"] ? "passed" : "failed"))

    def status
      return :finished if finished?
      return :paused if paused?

      alive? ? :running : :crashed
    end

    def running? = status == :running

    # Still going (or could resume going) — the frame poller and the live
    # tracker both keep polling through a pause, so a resume elsewhere shows
    # up without a manual reload.
    def active? = running? || status == :paused

    # Pass rate over scored runs with its 95% Wilson interval, as fractions:
    # [rate, low, high], or nil when nothing was scored. With 27 runs a
    # difference of a few points is noise; the interval says how much.
    def pass_rate
      n = scored
      return if n.zero?

      p = passed.fdiv(n)
      z = 1.96
      center = (p + ((z**2) / (2 * n))) / (1 + ((z**2) / n))
      half = z * Math.sqrt((p * (1 - p) / n) + ((z**2) / (4 * (n**2)))) / (1 + ((z**2) / n))
      [ p, (center - half).clamp(0, 1), (center + half).clamp(0, 1) ]
    end

    # :up / :down when this run's interval doesn't overlap `other`'s — a
    # change bigger than the noise; nil otherwise.
    def compared_to(other)
      mine = pass_rate
      theirs = other&.pass_rate
      return unless mine && theirs
      return :up if mine[1] > theirs[2]

      :down if mine[2] < theirs[1]
    end

    # Tokens over every turn, and the largest single step.
    def tokens
      turns = results.flat_map { |r| r["turns"] || [] }
      { input: turns.sum { |t| t["input_tokens"].to_i }, output: turns.sum { |t| t["output_tokens"].to_i },
        largest_step: turns.map { |t| t["max_step_input"].to_i }.max.to_i }
    end

    # { "04_lab_report_alone" => [passed, scored, errors] }
    def pass_counts
      results.group_by { |r| r["scenario"] }.transform_values do |list|
        statuses = list.map { |r| self.class.status(r) }
        [ statuses.count("passed"), statuses.count { |s| s != "error" }, statuses.count("error") ]
      end
    end

    def log_path = self.class.dir.join("#{id}.log")

    def log_tail(lines = 40)
      log_path.exist? ? log_path.readlines.last(lines).join : ""
    end

    private

    def alive?
      pid.present? && Process.kill(0, pid) && true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # SIGSTOP leaves the process alive but not running — read from the OS
    # rather than a flag in the file, so it's never out of sync with a pause
    # or resume sent from outside the dashboard (Launcher.pause! signals the
    # process directly; nothing round-trips through this file).
    def paused?
      return false unless alive?

      stat = File.read("/proc/#{pid}/stat")
      stat[(stat.rindex(")") + 2)] == "T"
    rescue Errno::ENOENT, Errno::ESRCH
      false
    end
  end
end
