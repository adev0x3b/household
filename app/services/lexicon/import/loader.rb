# frozen_string_literal: true

module Lexicon
  class Import
    # The streaming pass over one extract (download, parse, load): the
    # source read line by line, each noun kept as an Entry, the rows written
    # in batches, and the pivot's two-way synonyms linked. It counts what it
    # reads and writes into the counts it is given, and reports its progress
    # as it goes.
    class Loader
      BATCH = 2_000
      MAX_MALFORMED = 0.01
      PROGRESS_SECONDS = 2
      # A cheap test before parsing a line; the real one is Entry's pos check.
      # Not '"pos": "noun"': that would silently skip everything the day the
      # extract's JSON spacing changed.
      NOUN_MARK = '"noun"'

      def initialize(import, language, source, report, counts:)
        @import = import
        @language = language
        @source = source
        @report = report
        @counts = counts
        @pending = []
        @synonyms = {}
      end

      def load
        @started = clock
        STREAM_STEPS.each { |name| @report.mark(name, "running") }
        begin
          @source.each_line { |line| read(line) }
        rescue Source::Error => e
          raise StepFailed.new("download", e.message)
        end
        flush
        link_synonyms if @language.pivot?
        seconds = clock - @started

        @report.mark("download", "ok", "#{Import.size(@source.bytes_read)} from #{@source.local? ? "a local file" : URI(@source.label).host}", seconds)
        check_parse!
        @report.mark("parse", "ok", "#{@counts["lines"]} lines, #{@counts["nouns"]} nouns kept, #{@counts["malformed"]} malformed", seconds)
        @report.mark("load", "ok", "#{@counts["lemmas"]} nouns, #{@counts["forms"]} forms, #{@counts["meanings"]} meanings", seconds)
      rescue ActiveRecord::ActiveRecordError => e
        raise StepFailed.new("load", "#{e.class.name.demodulize}: #{e.message.truncate(300)}")
      end

      private

      def read(line)
        @counts["lines"] += 1
        progress if (@counts["lines"] % 2_000).zero? && clock - @last_progress.to_f >= PROGRESS_SECONDS
        return unless line.include?(NOUN_MARK)

        data = parse(line) or return
        @counts["candidates"] += 1
        entry = Entry.from_kaikki(data, pivot: @language.pivot?)
        return unless entry && (!@language.pivot? || entry.useful?)

        @counts["nouns"] += 1
        @pending << entry
        flush if @pending.size >= BATCH
      end

      # The line's JSON; nil for a malformed one, counted with where the first was.
      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        @counts["malformed"] += 1
        @first_malformed ||= "line #{@counts["lines"]}: #{e.message.squish.truncate(100)}"
        nil
      end

      def check_parse!
        checked = @counts["candidates"] + @counts["malformed"]
        if @counts["lines"].zero? || checked.zero?
          raise StepFailed.new("parse", "no nouns in #{@counts["lines"]} lines — is this a kaikki.org extract?")
        end

        share = @counts["malformed"].fdiv(checked)
        return if share <= MAX_MALFORMED

        raise StepFailed.new("parse", "#{@counts["malformed"]} of #{checked} noun lines are not valid JSON " \
                                      "(#{(share * 100).round(1)}%, over #{(MAX_MALFORMED * 100).round}%) — first at #{@first_malformed}")
      end

      def flush
        return if @pending.empty?

        rows = @pending.map { |entry| { lexicon_import_id: @import.id, word: entry.word, key: entry.key } }
        ids = LexiconLemma.insert_all!(rows, returning: %w[id]).rows.flatten
        forms = []
        meanings = []
        @pending.zip(ids) do |entry, lemma_id|
          entry.forms.each { |key| forms << { lexicon_import_id: @import.id, lexicon_lemma_id: lemma_id, key: key } }
          entry.meanings.each do |key, rank, qualified|
            meanings << { lexicon_import_id: @import.id, lexicon_lemma_id: lemma_id, key: key, rank: rank, qualified: qualified, kind: 0 }
          end
          @synonyms[entry.key] = (@synonyms[entry.key] || []) << [ lemma_id, entry.synonyms ] if entry.synonyms.any?
        end
        LexiconForm.insert_all!(forms) if forms.any?
        LexiconMeaning.insert_all!(meanings) if meanings.any?
        @counts["lemmas"] += ids.size
        @counts["forms"] += forms.size
        @counts["meanings"] += meanings.size
        @pending = []
      end

      # Synonyms only both ways: "vial" lists phial and phial lists vial —
      # one-way lists also hold related words (vial: beaker, jar…).
      def link_synonyms
        rows = []
        @synonyms.each do |key, entries|
          entries.each do |lemma_id, synonyms|
            synonyms.each do |synonym|
              next unless Array(@synonyms[synonym]).any? { |_, theirs| theirs.include?(key) }

              Text.english_keys(synonym).each do |variant|
                rows << { lexicon_import_id: @import.id, lexicon_lemma_id: lemma_id, key: variant, rank: 0, qualified: false, kind: 1 }
              end
            end
          end
        end
        rows.uniq.each_slice(BATCH * 5) { LexiconMeaning.insert_all!(_1) }
        @counts["meanings"] += rows.uniq.size
        @counts["synonyms"] = rows.uniq.size
      end

      # How far each of the streaming steps is, every PROGRESS_SECONDS.
      def progress
        @last_progress = clock
        seconds = clock - @started
        got = @source.bytes_read
        total = @source.expected_bytes
        download = total.to_i.positive? ? "#{Import.size(got)} of #{Import.size(total)} (#{(100.0 * got / total).floor}%)" : Import.size(got)
        download += " · #{Import.size(got / seconds)}/s" if seconds.positive?
        @report.progress("download" => download, "parse" => "#{@counts["lines"]} lines read, #{@counts["nouns"]} nouns kept",
                         "load" => "#{@counts["lemmas"]} nouns saved")
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
