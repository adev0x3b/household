# frozen_string_literal: true

require "test_helper"

# What a notification says: the same words on the bell's row, the toast and
# the push.
class Notifications::WordingTest < ActiveSupport::TestCase
  SHARED_THINGS = %w[event recipe grocery_list book bookshelf upload] + (Collection::SECTIONS + %w[other]).map { "collection.#{_1}" }
  VERBS = LinkApproval.action_kinds.keys + %w[destroy_series]

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
  end

  test "a share names who shared what, in the current language" do
    wording = wording_of(news(:shared, subject: @recipe, subject_title: "Roast chicken"))

    assert_equal [ "Alice shared a recipe with you", "Roast chicken" ], [ wording.title, wording.detail ]
    I18n.with_locale(:it) { assert_equal "Alice ha condiviso una ricetta con te", wording.title }
  end

  test "a shared collection is named as its section names it, and plainly once it is gone" do
    therapy = wording_of(news(:shared, subject: collections(:b12)))
    move = wording_of(news(:shared, subject: Collection.create!(profile: @alice, name: "Moving house", section: "agenda")))
    gone = wording_of(news(:unshared, subject_type: "Collection", subject_id: 0))

    assert_equal "Alice shared a therapy with you", therapy.title
    I18n.with_locale(:it) { assert_equal "Alice ha condiviso una terapia con te", therapy.title }
    assert_equal "Alice shared a collection with you", move.title
    assert_equal "Alice stopped sharing a collection with you", gone.title
  end

  test "without an actor it's someone, and a username stands in for a missing first name" do
    @alice.update!(first_name: "")

    assert_equal "Someone stopped sharing a recipe with you", wording_of(news(:unshared, actor: nil, subject: @recipe)).title
    assert_equal "alice shared a recipe with you", wording_of(news(:shared, subject: @recipe)).title
  end

  test "a job's end is worded by its kind, with what the job said underneath and how it went" do
    import = LexiconImport.create!(language: "it", status: :failed, error: "no nouns found")
    failed = wording_of(news(:import_failed, actor: nil, subject: import, data: { "language" => "Italian", "detail" => "no nouns found" }))
    finished = wording_of(news(:import_finished, actor: nil, subject: import, data: { "language" => "Italian" }))
    run = wording_of(news(:eval_run_finished, actor: nil, data: { "run_id" => "20260926-120000-qwen3", "model" => "qwen3", "passed" => 20, "total" => 27 }))

    assert_equal [ "The Italian import failed", "no nouns found", :alert ], [ failed.title, failed.detail, failed.toast_kind ]
    assert_equal :success, finished.toast_kind
    assert_equal [ "The eval run with qwen3 finished", "20 of 27 passed", :notice ], [ run.title, run.detail, run.toast_kind ]
    I18n.with_locale(:it) { assert_equal "20 su 27 superati", run.detail }
  end

  test "a linked housemate's request names what it asks and the kind of item" do
    asked = wording_of(news(:approval_requested, data: { "verb" => "destroy_series", "type" => "Task" }))
    unknown = wording_of(news(:approval_requested, data: { "type" => "Spaceship" }))

    assert_equal "Alice asks to delete your whole task series", asked.title
    assert_equal "Alice asks to change your item", unknown.title
  end

  test "a press on the delivery console says what it was, naming a destination it doesn't know as it came" do
    deployed = wording_of(news(:deploy_succeeded, actor: nil, data: { "action" => "deploy", "destination" => "staging" }))
    elsewhere = wording_of(news(:deploy_failed, actor: nil, data: { "action" => "deploy", "destination" => "mars" }))

    assert_equal [ "The deploy to Staging succeeded", "The deploy to mars failed" ], [ deployed.title, elsewhere.title ]
  end

  test "a press that ended without a run says why underneath, in the reader's language" do
    lost = news(:deploy_failed, actor: nil, data: { "action" => "deploy", "destination" => "staging", "outcome" => "lost" })

    assert_equal "Its run never showed up on GitHub.", wording_of(lost).detail
    I18n.with_locale(:it) { assert_equal "La sua esecuzione non è mai comparsa su GitHub.", wording_of(lost).detail }
  end

  test "a reminder says when it's due on the reader's clock, with or without a time of day" do
    @bob.update!(time_zone: "Europe/Rome")
    timed = wording_of(news(:reminder_due, actor: nil, data: { "due_at" => "2026-10-09T13:00:00Z", "timed" => true }))
    day = wording_of(news(:reminder_due, actor: nil, data: { "due_at" => "2026-10-09T13:00:00Z" }))

    assert_equal [ "Due Fri 9 Oct, 15:00", "Due Fri 9 Oct" ], [ timed.detail, day.detail ]
  end

  test "every kind has its words in every language" do
    I18n.available_locales.each do |locale|
      Notification.kinds.each_key do |kind|
        keys_for(kind).each { |key| assert I18n.exists?("notifications.kinds.#{key}", locale), "notifications.kinds.#{key} (#{locale})" }
      end
    end
  end

  private

  # Something Bob hears about, from Alice unless nobody did it.
  def news(kind, actor: @alice, **attributes) = Notification.new(profile: @bob, actor: actor, kind: kind, **attributes)

  def keys_for(kind)
    if Notifications::Wording::SHARE_KINDS.include?(kind) then SHARED_THINGS.map { "#{kind}.#{_1}" }
    elsif Notifications::Wording::APPROVAL_KINDS.include?(kind) then VERBS.map { "#{kind}.#{_1}" }
    elsif kind == "message_received" then %w[direct household].map { "#{kind}.#{_1}" }
    else [ kind ]
    end
  end
end
