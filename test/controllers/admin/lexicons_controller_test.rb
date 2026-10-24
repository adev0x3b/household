# frozen_string_literal: true

require "test_helper"

# /admin/lexicons: admins see every language and its report, and add one
# kaikki.org has; nobody else gets in.
class Admin::LexiconsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
    @member = profiles(:bob)
  end

  test "a member who isn't an admin is turned away from every page" do
    sign_in @member

    get admin_lexicons_path
    assert_redirected_to root_path
    post admin_lexicons_path, params: { lexicon_language: { wiktionary: "Spanish", head: "first" } }
    assert_redirected_to root_path
    assert_not LexiconLanguage.exists?(wiktionary: "Spanish")
  end

  test "the index lists every language, imported or not" do
    import_lexicon("it")
    sign_in @admin

    get admin_lexicons_path

    assert_response :success
    assert_select "title", text: /Languages/
    assert_select "a[href='#{new_admin_lexicon_path}'][data-turbo-stream]", 1, "Add a language, in the top bar"
    assert_select ".lexicons__row", LexiconLanguage.count
    assert_select ".lexicons__row", text: /Italian.*Active/m
    assert_select ".lexicons__row", text: /English.*Not imported/m
  end

  test "a failed import's page shows the step that failed and why" do
    import = import_lexicon("it", min_lemmas: 1_000_000)
    sign_in @admin

    get admin_lexicon_path("it", import: import.id)

    assert_response :success
    assert_select ".lexicons__step--failed", text: /Checks.*fewer than min_lemmas/m
    assert_select ".lexicons__step--skipped", text: /Activation/
    assert_select ".report-status--critical", text: /Failed.*Failed at Checks:/m
    assert_select "details.disclosure[open] summary", text: /Steps.*Failed at Checks/m
  end

  test "an active import's page is one status card and its sections closed, each saying how it went" do
    import = import_lexicon("it")
    sign_in @admin

    get admin_lexicon_path("it", import: import.id)

    assert_select ".report-status--good", text: /Active.*nouns/m
    assert_select(".report-segments__segment--good", import.steps.count { _1["status"] == "ok" })
    assert_select "details.disclosure:not([open]) summary", text: /Checks.*#{import.checks.size} of #{import.checks.size} passed/m
    assert_select "details.disclosure[data-disclosure-key-value='lexicon-#{import.id}-checks']"
  end

  test "an unknown language is a 404" do
    sign_in @admin

    get admin_lexicon_path("xx")
    assert_response :not_found
  end

  def peeking(code)
    swapping(Lexicon::Source, :new, ->(**) { Object.new.tap { |source| source.define_singleton_method(:peek) { { code: code, language: "x" } } } }) { yield }
  end

  test "an admin adds a language by its name: its code is read from the extract, and it's imported at once" do
    sign_in @admin

    peeking("es") do
      assert_enqueued_with(job: Lexicon::ImportJob) do
        post admin_lexicons_path, params: { lexicon_language: { wiktionary: "Spanish", head: "first" } }
      end
    end

    language = LexiconLanguage.find_by!(code: "es")
    assert_equal [ "Spanish", "first", "translated" ], [ language.wiktionary, language.head, language.role ]
    assert_redirected_to admin_lexicon_path("es")
    assert_predicate LexiconImport.find_by!(language: "es"), :running?
  end

  test "a language kaikki.org doesn't have is refused on the form, saying so" do
    sign_in @admin
    missing = ->(**) { Object.new.tap { |source| source.define_singleton_method(:peek) { raise Lexicon::Source::Error, "answered 404 Not Found" } } }

    swapping(Lexicon::Source, :new, missing) do
      post admin_lexicons_path, params: { lexicon_language: { wiktionary: "Klingonese", head: "first" } }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_match "kaikki.org has no Klingonese extract (answered 404 Not Found)", response.body
    assert_not LexiconLanguage.exists?(wiktionary: "Klingonese")
  end

  test "a language whose code is already here is refused" do
    sign_in @admin

    peeking("it") { post admin_lexicons_path, params: { lexicon_language: { wiktionary: "Italiano", head: "first" } }, as: :turbo_stream }

    assert_response :unprocessable_content
    assert_match "already uses here", response.body
  end

  test "the add form lists kaikki.org's languages, the ones already here left out" do
    sign_in @admin
    catalog = [ Lexicon::Catalog::Entry.new(name: "Spanish", senses: 875_726), Lexicon::Catalog::Entry.new(name: "Italian", senses: 719_680) ]

    swapping(Lexicon::Catalog, :languages, -> { catalog }) { get new_admin_lexicon_path, as: :turbo_stream }

    assert_response :success
    assert_match 'value="Spanish"', response.body
    assert_no_match 'value="Italian"', response.body
  end

  test "the page shows the agent evals: the grid, each failure with what the agent called, and the cases to fix" do
    import = import_lexicon("it")
    import.report["agent"] = { "status" => "failed", "detail" => "3/4 passed (75%), 0 wrong supply",
                               "results" => Lexicon::AgentEval::KINDS.map.with_index { |kind, i|
                                 { "scenario" => "it_needle_#{kind}", "status" => i.zero? ? "failed" : "passed",
                                   "failures" => i.zero? ? [ "medication_details: uses aghi 0.0" ] : [], "tools" => "update_record!" }
                               },
                               "review" => [ { "concept" => "gauze", "word" => "gause", "reason" => "not a word in the Italian dictionary" } ] }
    import.save!
    LexiconLanguage.find_by!(code: "it").lexicon_eval_cases.create!(concept: "gauze", native_singular: "gause", native_plural: "gause",
                                                                    dose_sentence: "…gause…", purchase_sentence: "…gause…")
    sign_in @admin

    get admin_lexicon_path("it", import: import.id)

    assert_response :success
    assert_select ".lexicons__grid:not(.lexicons__grid--picks) tbody tr", 1
    assert_select ".lexicons__grid--picks tbody tr", 16, "the dictionary check: 4 confirmed cases, both ways"
    assert_select ".lexicons__failures", text: /needle · Dose, saved in this language.*uses aghi 0.0.*update_record!/m
    assert_select ".lexicons__case", text: /gauze → gause.*not in the Italian dictionary/m
  end

  test "the pages work when the cache store is broken, as when its table was never created" do
    broken = Object.new.tap { |cache| cache.define_singleton_method(:fetch) { |*, **| raise ActiveRecord::StatementInvalid, "relation \"solid_cache_entries\" does not exist" } }
    import_lexicon("it")
    sign_in @admin

    swapping(Rails, :cache, -> { broken }) do
      get admin_lexicon_path("it")
      assert_response :success

      index = file_fixture("lexicon/kaikki_index.html").read
      swapping(Lexicon::Catalog, :download, -> { index }) { get new_admin_lexicon_path, as: :turbo_stream }
      assert_response :success
      assert_match 'value="Spanish"', response.body
    end
  end

  test "the page opens on the active import, announcing a newer failed attempt" do
    active = import_lexicon("it")
    import_lexicon("it", min_lemmas: 1_000_000)
    sign_in @admin

    get admin_lexicon_path("it")

    assert_select ".notice", text: /A newer attempt .*Failed.*see it/m
    assert_select ".lexicons__history li.is-current a[href*='import=#{active.id}']"
  end

  test "a running import shows its step, its progress, and how long it's been going" do
    import = LexiconImport.create!(language: "it", status: :running, started_at: 3.minutes.ago, report: Lexicon::Import.initial_report)
    import.report["steps"].find { _1["name"] == "download" }.merge!("status" => "running", "detail" => "45.2 MB of 72.3 MB (62%) · 1.4 MB/s",
                                                                    "started_at" => 2.minutes.ago.iso8601)
    import.report["updated_at"] = 5.seconds.ago.iso8601
    import.save!
    sign_in @admin

    get admin_lexicon_path("it", import: import.id)

    assert_select ".report-status", text: /Importing.*Download: 45.2 MB of 72.3 MB \(62%\).*running for 3 minutes.*last update less than a minute ago/m
    assert_select ".lexicons__step--running .lexicons__step-seconds", text: /for 2 minutes/
  end

  test "earlier imports come ten to a page, in their own frame" do
    12.times { |i| LexiconImport.create!(language: "it", status: :failed, failed_step: "download", created_at: i.days.ago, report: Lexicon::Import.initial_report) }
    sign_in @admin

    get admin_lexicon_path("it")
    assert_select "turbo-frame#lexicon-history .lexicons__history li", 10
    assert_select "turbo-frame#lexicon-history summary", text: /12/
    assert_select "nav.pagination a[href*='history_page=2'][data-turbo-frame='lexicon-history']"

    get admin_lexicon_path("it", history_page: 2)
    assert_select "turbo-frame#lexicon-history .lexicons__history li", 2
  end
end
