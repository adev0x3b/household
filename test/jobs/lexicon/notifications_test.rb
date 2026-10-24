# frozen_string_literal: true

require "test_helper"

# The lexicon's long jobs tell whoever started them how they ended.
class LexiconJobNotificationsTest < ActiveJob::TestCase
  setup do
    @admin = profiles(:alice)
    @italian = lexicon_languages(:it)
    @import = LexiconImport.create!(language: "it", status: :running, started_at: Time.current)
  end

  def importing(outcome, **job_args)
    import = @import
    swapping(Lexicon::Import, :call, ->(_language, **) { import.update!(**outcome) }) do
      Lexicon::ImportJob.perform_now(@import.id, **job_args)
    end
  end

  test "an import that fails says so, with its error" do
    importing({ status: :failed, error: "the file holds no nouns" }, notify: @admin.id)

    notification = @admin.notifications.sole
    assert_equal [ "import_failed", @import, "The Italian import failed", "the file holds no nouns" ],
                 [ notification.kind, notification.subject, wording_of(notification).title, wording_of(notification).detail ]
  end

  test "each way an import ends has its notification; a cancelled one has none" do
    { active: "import_finished", awaiting_review: "import_needs_review", unchanged: "import_unchanged" }.each do |status, kind|
      @import.update!(status: :running)
      importing({ status: status }, notify: @admin.id)
      assert_equal kind, @admin.notifications.recent_first.first.kind
    end

    @import.update!(status: :running)
    assert_no_difference("Notification.count") { importing({ status: :cancelled }, notify: @admin.id) }
  end

  test "an import nobody asked to hear about (a rake task) notifies nobody" do
    assert_no_difference("Notification.count") { importing({ status: :active }) }
  end

  test "an import that crashes still tells, once it's marked failed" do
    import = @import
    crash = ->(_language, **) { import.update!(status: :failed, error: "unexpected"); raise "boom" }

    swapping(Lexicon::Import, :call, crash) do
      assert_raises(RuntimeError) { Lexicon::ImportJob.perform_now(@import.id, notify: @admin.id) }
    end
    assert_equal "import_failed", @admin.notifications.sole.kind
  end

  test "writing the test cases tells when they're written, or why they couldn't be" do
    swapping(Lexicon::EvalCases, :generate!, ->(_language) { true }) do
      Lexicon::EvalCasesJob.perform_now(@italian.id, notify: @admin.id)
    end
    written = @admin.notifications.sole
    assert_equal [ "eval_cases_written", @italian, "The Italian test cases are written" ], [ written.kind, written.subject, wording_of(written).title ]

    swapping(Lexicon::EvalCases, :generate!, ->(_language) { raise Lexicon::EvalCases::Error, "the model didn't answer" }) do
      Lexicon::EvalCasesJob.perform_now(@italian.id, notify: @admin.id)
    end
    failed = @admin.notifications.recent_first.first
    assert_equal [ "eval_cases_failed", "the model didn't answer" ], [ failed.kind, wording_of(failed).detail ]
  end

  test "the checks with the assistant, run again, tell how they went" do
    @import.update!(status: :active)
    nothing = Struct.new(:run).new(nil)

    swapping(Lexicon::AgentEval, :new, ->(*, **) { nothing }) do
      Lexicon::AgentEvalJob.perform_now(@import.id, notify: @admin.id)
    end

    notification = @admin.notifications.sole
    assert_equal [ "lexicon_eval_failed", @import, "nothing to test with" ], [ notification.kind, notification.subject, wording_of(notification).detail ]
  end
end
