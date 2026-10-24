# frozen_string_literal: true

require "test_helper"

class Assistant::Evals::RunWordsTest < ActiveSupport::TestCase
  test "a run names its model on its provider's name" do
    words = words_for("model" => "qwen3:8b", "provider" => "ollama")

    assert_equal I18n.t("assistant.evals.run.model_on_provider", model: "qwen3:8b",
                                                                 provider: I18n.t("assistant.settings.providers.ollama.name")), words.model_line
  end

  test "a run resumed past its planned total counts what it did" do
    words = words_for("total" => 1, "results" => [ result(true), result(false) ])

    assert_equal I18n.t("assistant.evals.run.progress", done: 2, total: 2), words.progress
  end

  test "the score and its interval read as percentages of what was scored" do
    words = words_for("results" => [ result(true), result(true), result(false), { "status" => "error" } ])

    assert_predicate words, :scored?
    assert_equal "67%", words.rate
    assert_match(/\A\d+%\z/, words.low)
    assert_match(/\A\d+%\z/, words.high)
  end

  test "a run with nothing scored has no score to give" do
    words = words_for("results" => [ { "status" => "error" } ])

    assert_not_predicate words, :scored?
    assert_equal I18n.t("statistics.no_data"), words.rate
  end

  test "a finished run whose file is gone says nothing of how long it took" do
    assert_nil words_for("started_at" => 1.hour.ago.iso8601).timing
  end

  private

  def words_for(data)
    run = AssistantEval::RunFile.new("words", { "model" => "qwen", "provider" => "ollama", "finished" => true }.merge(data))
    Assistant::Evals::RunWords.new(run)
  end

  def result(passed) = { "scenario" => "a", "passed" => passed }
end
