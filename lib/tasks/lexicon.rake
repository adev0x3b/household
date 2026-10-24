# frozen_string_literal: true

# The lexicon's languages (LexiconLanguage), imported from kaikki.org.
# See "The lexicon" in docs/architecture/assistant.md.
namespace :lexicon do
  print_step = lambda do |step|
    next if step["status"] == "running"

    mark = { "ok" => "✓", "failed" => "✗", "skipped" => "·", "waiting" => "…", "pending" => " " }.fetch(step["status"], "?")
    seconds = step["seconds"] ? format("%5.1fs ", step["seconds"]) : "       "
    puts "  #{mark} #{step["name"].ljust(10)}#{seconds}#{step["detail"]}"
  end

  print_checks = lambda do |checks|
    checks.each { |check| puts "      #{check["ok"] ? "✓" : "✗"} #{check["check"]}  → #{check["got"]}" }
  end

  desc "Add a language kaikki.org has: lexicon:add[Spanish] (or [Spanish,last] when a name's noun is its last word); its code is read from the extract"
  task :add, %i[wiktionary head] => :environment do |_, args|
    abort "usage: bin/rails \"lexicon:add[Spanish]\" — kaikki.org's English name of the language (https://kaikki.org/dictionary/)" if args[:wiktionary].blank?

    result = Lexicon::AddLanguage.call(args[:wiktionary], head: args[:head])
    language = result.language
    abort "✗ #{language.errors.full_messages.to_sentence}" if result.failure?

    puts "✓ added #{language.wiktionary} (#{language.code}), head: #{language.head}"
    puts "Next: bin/rails \"lexicon:import[#{language.code}]\" — or Import on /admin/lexicons"
  end

  desc "Import languages from kaikki.org: lexicon:import[it] (all when none given); FORCE=1 even if unchanged, " \
       "SOURCE=file.jsonl.gz for a local extract, DOWNLOAD=0 for the file the last download kept, AGENT=skip to activate without the agent evals"
  task :import, %i[code] => :environment do |_, args|
    codes = args[:code].present? ? [ args[:code].to_s ] : Lexicon::Config.codes.sort_by { Lexicon::Config.languages[_1].pivot? ? 0 : 1 }
    abort "SOURCE= imports one language: name it, lexicon:import[it]" if ENV["SOURCE"].present? && codes.size > 1

    failed = codes.reject do |code|
      puts "#{code}:"
      import = Lexicon::Import.call(code, source: ENV["SOURCE"], download: ENV["DOWNLOAD"] != "0", force: ENV["FORCE"] == "1",
                                          on_step: print_step, agent: (:skip if ENV["AGENT"] == "skip"))
      print_checks.call(import.checks)
      puts "  → #{import.status}#{" at #{import.failed_step}" if import.failed?}"
      !import.failed?
    end
    abort "✗ failed: #{failed.join(", ")} — the active data of each is unchanged" if failed.any?
  end

  desc "Go on with an import waiting for review, once its test cases are confirmed: lexicon:continue[it]"
  task :continue, %i[code] => :environment do |_, args|
    import = LexiconImport.awaiting_review.where(language: args[:code].to_s).latest_first.first
    abort "#{args[:code]}: no import is waiting for review" unless import

    import = Lexicon::Import.call(import.language, import: import, resume: true, on_step: print_step,
                                                   agent: (:skip if ENV["AGENT"] == "skip"))
    puts "  → #{import.status}#{" at #{import.failed_step}" if import.failed?}"
    abort "✗ #{import.error}" if import.failed?
  end

  desc "Stop a language's import that's running or waiting for review: lexicon:cancel[it]"
  task :cancel, %i[code] => :environment do |_, args|
    import = LexiconImport.where(language: args[:code].to_s, status: %i[running awaiting_review]).latest_first.first
    abort "#{args[:code]}: no import is running or waiting" unless import

    puts({ stopping: "##{import.id} is asked to stop; it ends within a few seconds",
           cancelled: "##{import.id} is cancelled", finished: "##{import.id} had already finished" }.fetch(import.cancel!))
  end

  desc "Rerun a language's checks on its active data: lexicon:verify[it] (all when none given)"
  task :verify, %i[code] => :environment do |_, args|
    codes = args[:code].present? ? [ args[:code].to_s ] : Lexicon::Config.codes
    failed = codes.reject do |code|
      language = Lexicon::Config.fetch(code)
      import = LexiconImport.active_for(code)
      next(puts "#{code}: ✗ not imported — bin/rails \"lexicon:import[#{code}]\"") unless import

      results = Lexicon::Verification.new(import, language).run
      puts "#{code}: import ##{import.id} of #{import.finished_at&.to_date}, #{import.lemma_count} nouns"
      print_checks.call(results.map(&:to_h))
      results.all?(&:ok)
    end
    abort "✗ checks failed: #{failed.join(", ")}" if failed.any?
  end

  desc "Each language: its active import, its last attempt, and anything wrong in config/lexicons.yml"
  task status: :environment do
    Lexicon::Config.problems.each { puts "✗ config: #{_1}" }
    Lexicon::Config.languages.each_value do |language|
      active = LexiconImport.active_for(language.code)
      last = LexiconImport.where(language: language.code).latest_first.first
      line = active ? "#{active.lemma_count} nouns, imported #{active.finished_at&.to_date}, source of #{active.source_last_modified&.to_date}" : "not imported"
      puts "#{language.code.ljust(4)}#{language.wiktionary.ljust(12)}#{line}"
      if last && last != active
        puts "    last attempt ##{last.id} #{last.created_at.to_date}: #{last.status}#{" at #{last.failed_step}: #{last.error}" if last.failed?}"
      end
    end
  end
end
