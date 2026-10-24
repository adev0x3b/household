# frozen_string_literal: true

require "test_helper"

# Lexicon::StartImport: the import the page shows at once and its job, one
# import at a time per language.
class Lexicon::StartImportTest < ActiveJob::TestCase
  test "an import is created with every step pending and its job queued for whoever started it" do
    result = nil
    assert_enqueued_with(job: Lexicon::ImportJob) { result = Lexicon::StartImport.call(lexicon_languages(:it), by: profiles(:alice)) }

    assert_predicate result, :success?
    assert_predicate result.import, :running?
    assert_equal Lexicon::Import.initial_report, result.import.report
    assert_equal({ "download" => true, "notify" => profiles(:alice).id }, enqueued_jobs.last[:args].last.except("_aj_ruby2_keywords"))
  end

  test "a second is refused while the first is really going" do
    Lexicon::StartImport.call(lexicon_languages(:it), by: profiles(:alice))
    result = Lexicon::StartImport.call(lexicon_languages(:it), by: profiles(:alice))

    assert_equal :already_running, result.error
    assert_nil result.import
    assert_equal 1, LexiconImport.count
  end
end
