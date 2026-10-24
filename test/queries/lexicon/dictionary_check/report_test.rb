# frozen_string_literal: true

require "test_helper"

# The dictionary check read back from an import's report.
class Lexicon::DictionaryCheck::ReportTest < ActiveSupport::TestCase
  test "each pick keeps what was said, among which supplies, and what came of it" do
    import = LexiconImport.new(report: { "dictionary" => { "status" => "passed", "detail" => "1/1 picked right", "results" => [
                                 { "said" => "aghi", "supplies" => %w[Needles Syringes], "expected" => "Needles", "got" => "Needles", "verdict" => "found" }
                               ] } })
    report = Lexicon::DictionaryCheck::Report.of(import)

    assert_predicate report, :passed?
    pick = report.results.sole
    assert_equal [ "aghi", %w[Needles Syringes], "Needles", "found" ], [ pick.said, pick.supplies, pick.got, pick.verdict ]
    assert_not Lexicon::DictionaryCheck::Report.of(nil).any?
  end
end
