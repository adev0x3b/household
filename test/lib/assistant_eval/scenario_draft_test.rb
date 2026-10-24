# frozen_string_literal: true

require "test_helper"

class AssistantEval::ScenarioDraftTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    @real = AssistantEval::Scenario.all # the real eval/assistant/scenarios files, read before pointing elsewhere
    AssistantEval::Scenario.dir = @dir
  end

  teardown do
    AssistantEval::Scenario.dir = nil
    FileUtils.remove_entry(@dir)
  end

  def draft(**overrides)
    AssistantEval::ScenarioDraft.new(name: "10_skip_todays_dose", today: "2026-09-26", messages: [ "I'm skipping today's injection" ],
                                     expect: [ { "check" => "lab_results", "argument" => "0" } ], **overrides)
  end

  test "every existing scenario survives the form and a save unchanged" do
    @real.each do |scenario|
      form = AssistantEval::ScenarioDraft.from_scenario(scenario)
      assert_equal scenario, form.to_scenario, "#{scenario.name} changed going through the form"

      form.original_name = nil # a copy into the temp dir
      form.save!
      assert_equal scenario, AssistantEval::Scenario.load(@dir.join("#{scenario.name}.yml")), "#{scenario.name} changed on disk"
    end
  end

  test "a save writes the file and a rename moves it" do
    form = draft
    form.save!
    assert_predicate @dir.join("10_skip_todays_dose.yml"), :exist?

    form.assign(name: "10_skip_a_dose", today: "2026-09-26", messages: [ "skip it" ], expect: [ { check: "lab_results", argument: "0" } ])
    form.save!
    assert_predicate @dir.join("10_skip_a_dose.yml"), :exist?
    assert_not @dir.join("10_skip_todays_dose.yml").exist?
  end

  test "bad names, dates, buttons, seeds and checks are refused with row numbers" do
    form = draft(name: "Skip!", today: "tomorrow", seed: [ "nope" ], messages: [ "hi", "!approve", "@2026-13-40 later" ],
                 expect: [ { "check" => "lab_count", "argument" => "1" }, { "check" => "lab_values", "argument" => "a: [" },
                           { "check" => "lab_status", "argument" => "" } ])

    assert_not form.valid?
    assert form.errors.added?(:name, :name_format)
    assert form.errors.added?(:today, :not_a_date)
    assert form.errors.added?(:seed, :unknown, names: "nope")
    assert form.errors.added?(:messages, :unknown_button, row: 2, buttons: "!confirm, !undo")
    assert form.errors.added?(:messages, :bad_date, row: 3)
    assert form.errors.added?(:expect, :unknown_check, row: 1, check: "lab_count")
    assert(form.errors.details[:expect].any? { |e| e[:error] == :bad_yaml && e[:row] == 2 })
    assert form.errors.added?(:expect, :missing_value, row: 3, check: "lab_status")
  end

  test "tags come from a comma list and must be single words" do
    form = draft.assign(name: "10_skip_todays_dose", today: "2026-09-26", messages: [ "skip it" ],
                        expect: [ { check: "lab_results", argument: "0" } ], tags: "Coverage, labs  status")
    assert_equal %w[coverage labs status], form.tags
    assert_predicate form, :valid?

    form.tags = [ "two words" ]
    assert_not form.valid?
    assert form.errors.added?(:tags, :not_words, tags: "two words")
  end

  test "saving needs a check and a free name; trying doesn't need a check" do
    assert_predicate draft(expect: []), :valid?, "a try can run without checks"
    assert_not draft(expect: []).valid?(:save)

    draft.save!
    taken = draft
    assert_not taken.valid?
    assert taken.errors.added?(:name, :taken)
  end

  test "a real chat becomes messages: later days get their @date, button presses become !confirm / !undo" do
    chat = assistant_chat(profiles(:alice))
    chat.assistant_messages.create!(role: "user", content: "Booked Moretti for Friday", created_at: Time.utc(2026, 9, 21, 10))
    chat.assistant_messages.create!(role: "assistant", content: "Saved.", created_at: Time.utc(2026, 9, 21, 10, 1))
    chat.note_for_model!("Change set 5: The user pressed Apply: the changes were saved.")
    chat.assistant_messages.where(hidden: true).update_all(created_at: Time.utc(2026, 9, 21, 10, 2))
    chat.assistant_messages.create!(role: "user", content: "The visit is done", created_at: Time.utc(2026, 9, 25, 10))

    form = AssistantEval::ScenarioDraft.from_chat(chat)

    assert_equal "2026-09-21", form.today
    assert_equal [ "Booked Moretti for Friday", "!confirm", "@2026-09-25 The visit is done" ], form.messages
    assert_match(/\A01_from_chat_#{chat.id}\z/, form.name)
  end

  test "photos in a chat become a !photo turn with the text read from each, which validates" do
    chat = assistant_chat(profiles(:alice))
    content = Assistant::LabReportOcrJob.attach_text("Sent a photo", [ "Glucosio 92 mg/dL 70 - 99", nil, "Creatinina 0,9 mg/dL 0,5 - 1,1" ])
    chat.assistant_messages.create!(role: "user", content: content, created_at: Time.utc(2026, 9, 21, 10))

    form = AssistantEval::ScenarioDraft.from_chat(chat)

    assert_equal [ "!photo\nGlucosio 92 mg/dL 70 - 99\n---\n\n---\nCreatinina 0,9 mg/dL 0,5 - 1,1" ], form.messages
    form.expect = [ { "lab_results" => 1 } ]
    form.valid?
    assert_not form.errors.include?(:messages), form.errors.full_messages.inspect
  end
end
