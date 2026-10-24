# frozen_string_literal: true

require "test_helper"

# A language's test cases on its page: written again by the model, fixed by
# hand, confirmed as written, added for a supply of the admin's own, and
# deleted when they are the admin's own.
class Admin::LexiconCasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
  end

  test "a case fixed by hand is saved as confirmed" do
    language = lexicon_languages(:it)
    kase = language.lexicon_eval_cases.create!(concept: "gauze", native_singular: "gause", native_plural: "gause",
                                               dose_sentence: "a", purchase_sentence: "b")
    sign_in @admin

    get edit_admin_lexicon_case_path("it", kase), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='lexicon_eval_case[native_plural]'][value=gause]", admin_lexicon_case_path("it", kase)

    patch admin_lexicon_case_path("it", kase), params: { lexicon_eval_case: { native_singular: "garza", native_plural: "garze" } }

    assert_redirected_to admin_lexicon_path("it")
    assert_equal [ "garze", true ], [ kase.reload.native_plural, kase.confirmed ]
  end

  test "writing the cases again queues the model" do
    sign_in @admin

    assert_enqueued_with(job: Lexicon::EvalCasesJob) { post write_admin_lexicon_cases_path("it") }
  end

  test "a case confirmed as written counts from then on" do
    kase = italian_cases!({ "vial" => %w[fiala fiale] }, confirmed: false).lexicon_eval_cases.find_by!(concept: "vial")
    sign_in @admin

    patch confirm_admin_lexicon_case_path("it", kase)

    assert_redirected_to admin_lexicon_path("it")
    assert_predicate kase.reload, :confirmed?
  end

  test "a case for a supply of the admin's own is created confirmed, with its English plural, and can be deleted" do
    italian_cases!
    sign_in @admin

    get new_admin_lexicon_case_path("it"), as: :turbo_stream
    assert_select "datalist#lexicon-concepts option[value='gauze']"
    assert_select "datalist#lexicon-concepts option[value='needle']", 0, "needle has a case already"

    post admin_lexicon_cases_path("it"), params: { lexicon_eval_case: { concept: " Pill Box ", english_plural: "pill boxes", native_singular: "portapillole",
                                                                        native_plural: "portapillole", dose_sentence: "a", purchase_sentence: "b" } }
    kase = LexiconLanguage.find_by!(code: "it").lexicon_eval_cases.find_by!(concept: "pill box")
    assert_redirected_to admin_lexicon_path("it")
    assert_predicate kase, :confirmed?
    assert_not kase.shared?
    assert_equal "pill boxes", Lexicon::EvalCases.english_plural(kase)

    get admin_lexicon_path("it")
    assert_select ".lexicons__case", text: /pill box.*added here/m
    assert_select "a.item-action--danger[href='#{admin_lexicon_case_path("it", kase)}'][data-turbo-method=delete]", 1, "only the admin's own case"

    delete admin_lexicon_case_path("it", kase)
    assert_not LexiconEvalCase.exists?(kase.id)
  end

  test "a new case for a supply that has one already shows the form again; a shared case can't be deleted" do
    language = italian_cases!
    sign_in @admin

    post admin_lexicon_cases_path("it"), params: { lexicon_eval_case: { concept: "Needle", native_singular: "ago", native_plural: "aghi",
                                                                        dose_sentence: "a", purchase_sentence: "b" } }
    assert_response :unprocessable_content
    assert_match "lexicon_eval_case_concept", response.body

    needle = language.lexicon_eval_cases.find_by!(concept: "needle")
    delete admin_lexicon_case_path("it", needle)
    assert LexiconEvalCase.exists?(needle.id)
  end

  test "cases come ten to a page, those waiting for the admin first, and the page is kept through a confirm" do
    language = italian_cases!
    8.times { |i| language.lexicon_eval_cases.create!(concept: "thing #{i}", native_singular: "x", native_plural: "x#{i}", dose_sentence: "a", purchase_sentence: "b", confirmed: true) }
    waiting = language.lexicon_eval_cases.create!(concept: "zz last", native_singular: "z", native_plural: "zz", dose_sentence: "a", purchase_sentence: "b")
    sign_in @admin

    get admin_lexicon_path("it")
    assert_select ".lexicons__case", 10
    assert_select ".lexicons__case:first-child", text: /zz last/, message: "unconfirmed first"
    assert_select "nav.pagination a[href*='cases_page=2'][data-turbo-frame='lexicon-import']"

    get admin_lexicon_path("it", cases_page: 2)
    assert_select ".lexicons__case", 3

    patch confirm_admin_lexicon_case_path("it", waiting, cases_page: 2)
    assert_redirected_to admin_lexicon_path("it", cases_page: 2)
  end
end
