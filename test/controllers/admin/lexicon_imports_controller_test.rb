# frozen_string_literal: true

require "test_helper"

# A language's imports: Import queues a job on a record the page shows at
# once, an import waiting for review goes on, any import still going can be
# stopped, and the active one is tested against the assistant again.
class Admin::LexiconImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
  end

  test "a member who isn't an admin can't import" do
    sign_in profiles(:bob)

    post admin_lexicon_imports_path("it")
    assert_redirected_to root_path
    assert_no_enqueued_jobs
  end

  test "Import creates the import the page shows and queues its job" do
    sign_in @admin

    assert_enqueued_with(job: Lexicon::ImportJob) { post admin_lexicon_imports_path("it") }

    import = LexiconImport.last
    assert_predicate import, :running?
    assert_equal "pending", import.steps.first["status"]
    assert_redirected_to admin_lexicon_path("it")
  end

  test "Import is refused while that language is already importing" do
    LexiconImport.create!(language: "it", status: :running, started_at: 1.minute.ago)
    sign_in @admin

    assert_no_enqueued_jobs { post admin_lexicon_imports_path("it") }
    assert_equal 1, LexiconImport.count
  end

  test "re-running the agent evals queues them on the active import, once" do
    import = import_lexicon("it")
    sign_in @admin

    assert_enqueued_with(job: Lexicon::AgentEvalJob, args: [ import.id, { notify: @admin.id } ]) { post evaluate_admin_lexicon_import_path("it", import) }
    assert_equal "running", import.reload.report.dig("agent", "status")
    assert_no_enqueued_jobs { post evaluate_admin_lexicon_import_path("it", import) }
  end

  test "an import waiting for review says what to do, and Continue goes on with it" do
    italian_cases!(confirmed: false)
    import = import_lexicon("it")
    sign_in @admin

    get admin_lexicon_path("it")
    assert_select ".notice--action", text: /confirm at least 3 test cases/
    assert_select ".lexicons__case", 4
    assert_select ".report-flag", text: /not confirmed yet/, minimum: 1

    assert_enqueued_with(job: Lexicon::ImportJob, args: [ import.id, { resume: true, notify: @admin.id } ]) { post resume_admin_lexicon_import_path("it", import) }
  end

  test "Import opens a modal offering a new download, and the kept file only when there is one" do
    sign_in @admin
    head = ->(**) { Object.new.tap { |source| source.define_singleton_method(:head) { { size: 75_783_172, last_modified: Time.zone.local(2026, 9, 28) } } } }

    swapping(Lexicon::Source, :new, head) { get new_admin_lexicon_import_path("it"), as: :turbo_stream }

    assert_response :success
    assert_match "kaikki.org has 72.3 MB", response.body
    assert_select "input[type=radio][value='0'][disabled]", 1, "nothing kept yet"
    assert_select "input[type=radio][value='1'][checked]", 1
  end

  test "importing with the kept file queues the full import on it; with none kept, it downloads" do
    sign_in @admin
    Lexicon::Downloads.dir = Dir.mktmpdir
    FileUtils.cp(file_fixture("lexicon/italian_sample.jsonl.gz"), Lexicon::Downloads.path("it"))

    post admin_lexicon_imports_path("it"), params: { download: "0" }
    assert_equal({ "download" => false, "notify" => @admin.id }, enqueued_jobs.last[:args].last.except("_aj_ruby2_keywords"))
    post admin_lexicon_imports_path("en"), params: { download: "0" }
    assert_equal({ "download" => true, "notify" => @admin.id }, enqueued_jobs.last[:args].last.except("_aj_ruby2_keywords"), "nothing kept for English")
  ensure
    FileUtils.rm_rf(Lexicon::Downloads.dir) if Lexicon::Downloads.dir.to_s.start_with?(Dir.tmpdir)
    Lexicon::Downloads.dir = nil
  end

  test "an import whose job never came says so, offers Cancel, and Cancel ends it" do
    orphan = LexiconImport.create!(language: "it", status: :running, started_at: 4.hours.ago, created_at: 4.hours.ago,
                                   updated_at: 4.hours.ago, report: Lexicon::Import.initial_report)
    sign_in @admin

    get admin_lexicon_path("it", import: orphan.id)
    assert_select ".report-status--action", text: /Its job isn't there/
    assert_select "a[href=?][data-turbo-method=post]", cancel_admin_lexicon_import_path("it", orphan)

    post cancel_admin_lexicon_import_path("it", orphan)
    assert_predicate orphan.reload, :cancelled?
  end

  test "an import that moved on since the page was drawn is shown, not continued or stopped" do
    import = import_lexicon("it")
    sign_in @admin

    assert_no_enqueued_jobs { post resume_admin_lexicon_import_path("it", import) }
    assert_redirected_to admin_lexicon_path("it", import: import.id)

    post cancel_admin_lexicon_import_path("it", import)
    assert_predicate import.reload, :active?
    assert_equal "Italian's import had already finished: nothing to stop.", flash[:alert]
  end

  test "the assistant tests run again on the active import only" do
    failed = import_lexicon("it", min_lemmas: 1_000_000)
    sign_in @admin

    assert_no_enqueued_jobs { post evaluate_admin_lexicon_import_path("it", failed) }
    assert_redirected_to admin_lexicon_path("it")
  end

  test "another language's import is a 404" do
    english = LexiconImport.create!(language: "en", status: :running, started_at: Time.current, report: Lexicon::Import.initial_report)
    sign_in @admin

    post cancel_admin_lexicon_import_path("it", english)
    assert_response :not_found
    assert_predicate english.reload, :running?
  end

  test "an import whose job can't be queued has failed, and the toast says why" do
    sign_in @admin

    assert_error_reported(ActiveJob::EnqueueError) do
      swapping(Lexicon::ImportJob, :perform_later, ->(*, **) { Lexicon::ImportJob.new }) { post admin_lexicon_imports_path("it") }
    end

    import = LexiconImport.sole
    assert_predicate import, :failed?
    assert_equal import.error, flash[:alert]
    assert_match "is the job worker set up?", import.error
  end
end
