# frozen_string_literal: true

require "test_helper"

# Every kind of event the eval's recorder writes to the timeline has its entry.
class Views::Assistant::Evals::TimelineTest < ActiveSupport::TestCase
  WRITTEN = %w[scenario_started turn_started tool_started tool_call reply turn_finished scenario_finished run_finished
               outage_started outage_ended].freeze

  test "each kind of event is drawn by its own entry, and an unknown kind is an error" do
    WRITTEN.each do |type|
      assert_kind_of Views::Assistant::Evals::Timeline::Entry, Views::Assistant::Evals::Timeline.for("type" => type), type
    end
    assert_raises(KeyError) { Views::Assistant::Evals::Timeline.for("type" => "run_started") }
  end

  test "a tool call is drawn running, then finished under the same id; a reply folds the model's thinking away" do
    started = render("type" => "tool_started", "seq" => 3, "tool" => "record_lab_results", "arguments" => { "values" => [] })
    finished = render("type" => "tool_call", "seq" => 3, "tool" => "record_lab_results", "ok" => false, "error" => "give values", "ms" => 12)
    reply = render("type" => "reply", "turn" => "0-1", "text" => "<think>maybe</think>Done.")

    assert_equal "eval-tool-3", started.at_css("li")["id"]
    assert_includes started.at_css("li")["class"], "eval-tl--running"
    assert_equal "eval-tool-3", finished.at_css("li")["id"]
    assert_includes finished.at_css("li")["class"], "eval-tl--failed"
    assert_equal "give values", finished.at_css(".eval-tl__error").text
    assert_equal [ "maybe", "Done." ], [ reply.at_css(".eval-tl__thinking p").text, reply.at_css(".eval-tl__reply").text ]
  end

  private

  def render(event) = Nokogiri::HTML5.fragment(ApplicationController.render(Views::Assistant::Evals::Timeline.for(event), layout: false))
end
