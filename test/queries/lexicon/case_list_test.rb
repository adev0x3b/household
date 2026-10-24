# frozen_string_literal: true

require "test_helper"

# Lexicon::CaseList: a language's eval cases as its admin page lists them,
# what needs a look first, with why each waits.
class Lexicon::CaseListTest < ActiveSupport::TestCase
  setup do
    import_lexicons
    @italian = LexiconLanguage.find_by!(code: "it")
  end

  def add_case(concept, plural, confirmed:)
    @italian.lexicon_eval_cases.create!(concept: concept, native_singular: plural, native_plural: plural, confirmed: confirmed,
                                        dose_sentence: "uso #{plural}", purchase_sentence: "ho comprato #{plural}")
  end

  test "what waits comes first, with its reason; the rest by concept, and an admin's own is told apart" do
    add_case("lancet", "aghi", confirmed: true)
    gauze = add_case("gauze", "gause", confirmed: false)
    own = add_case("cotton swab", "cotton fioc", confirmed: true)

    list = Lexicon::CaseList.new(@italian, import: LexiconImport.active_for("it"), page: nil)

    assert_equal [ "gauze", "lancet" ], list.shown.first(2).map(&:concept), "the unconfirmed and the duplicate lead"
    assert_equal :not_in_dictionary, list.reason(gauze)
    assert_nil list.reason(list.cases.find { _1.concept == "needle" })
    assert_equal 1, list.unconfirmed_count
    assert list.own?(own)
    assert_not list.own?(gauze)
  end

  test "ten to a page, and a page past the last is the last" do
    12.times { |i| add_case("thing #{i}", "cosa #{i}", confirmed: true) }
    size = @italian.lexicon_eval_cases.count

    last = Lexicon::CaseList.new(@italian, import: nil, page: "99").shown

    assert_equal (size / 10.0).ceil, last.current_page
    assert_equal size - ((last.current_page - 1) * 10), last.size
  end
end
