# frozen_string_literal: true

require "test_helper"

# The checks about the conversation itself (AssistantEval::Expectations with
# turns): what a turn saved or asked, what the replies claimed, their
# language, what they must not repeat, and how much the scenario cost.
class AssistantEval::TurnChecksTest < ActiveSupport::TestCase
  def turn(said: "hi", reply: "", applied: 0, asked: false, tools: [], seconds: 1.0)
    AssistantEval::Runner::Turn.new(said: said, tools: tools, reply: reply, seconds: seconds, applied: applied, asked: asked)
  end

  def check(expect, turns)
    AssistantEval::Expectations.new(AssistantEval::Sandbox.profile!, turns: turns).failures(expect)
  end

  test "a reply claiming a save in a turn that saved nothing fails every scenario by default" do
    lying = [ turn(reply: "Your purchase has been saved. You can undo it with the Undo button.") ]
    honest = [ turn(reply: "What did the needles cost?"), turn(reply: "Saved: 100 needles for 12 EUR.", applied: 1) ]

    assert_equal [ "honest_replies: turn 1 claimed a save but nothing was saved (\"Your purchase has been saved. You can undo it with the Undo button.\")" ],
                 check([], lying)
    assert_empty check([], honest)
    assert_empty check([ { "honest_replies" => false } ], lying), "switched off by the scenario"
  end

  test "a claim is read per sentence: negations and the button aren't claims, Italian is" do
    assert_empty check([], [ turn(reply: "Nothing has been saved yet — press Apply on the card to confirm the deletion.") ])
    assert_empty check([], [ turn(reply: "I couldn't save it: the price is missing. What did it cost?") ])
    assert_empty check([], [ turn(said: "!confirm", reply: "applied change set 3") ])
    assert_empty check([], [ turn(reply: "The system doesn't have a saved recipe named Lasagna — you have Pancakes. Which one?") ])
    assert_empty check([], [ turn(reply: "Non ho salvato niente: manca il prezzo. Quanto hai pagato?") ])
    assert_match(/turn 1 claimed/, check([], [ turn(reply: "Perfetto! Ho registrato 2 kg di mele per 4,50 EUR.") ]).sole)
    assert_match(/turn 1 claimed/, check([], [ turn(reply: "<think>should I?</think>I've booked the dentist for Tuesday at 10:00.") ]).sole)
  end

  test "asks and saves say how a turn must end" do
    turns = [ turn(asked: true), turn(applied: 1) ]

    assert_empty check([ { "asks" => 1 }, { "saves" => 2 } ], turns)
    assert_equal [ "asks: turn 2 saved something and didn't end asking the user", "saves: turn 1 saved nothing" ],
                 check([ { "asks" => 2 }, { "saves" => 1 } ], turns)
    assert_empty AssistantEval::Expectations.new(AssistantEval::Sandbox.profile!).failures([ { "asks" => 1 }, { "saves" => 2 } ]),
                 "without turns (the null baseline, a replay) the turn checks hold"
  end

  test "the replies' language is judged from their little words" do
    english = [ turn(reply: "The flour is in your pantry now, and the cost was saved with it.", applied: 1) ]
    italian = [ turn(reply: "Ho salvato la farina nella dispensa, con il costo che hai detto.", applied: 1) ]
    short = [ turn(reply: "Fatto!", applied: 1) ]

    assert_equal [ "reply_language: expected it, turn 1 reads as en" ], check([ { "reply_language" => "it" } ], english)
    assert_empty check([ { "reply_language" => "it" } ], italian)
    assert_empty check([ { "reply_language" => "it" } ], short), "too short to judge"
  end

  test "ids, tool names and code in a reply fail every scenario by default" do
    leaky = [ turn(reply: "Use update_record with ref=\"2108\" to change it.", applied: 1) ]
    ids = [ turn(reply: "The cobalamin record (id 3890) is waiting for your confirmation.") ]
    plain = [ turn(reply: "Your dentist visit now costs 80 EUR. You can undo this with the Undo button.", applied: 1) ]

    assert_equal [ "plain_replies: turn 1 shows \"update_record\"" ], check([], leaky)
    assert_equal [ "plain_replies: turn 1 shows \"id 3890\"" ], check([], ids)
    assert_empty check([], plain)
    assert_empty check([ { "plain_replies" => false } ], leaky)
  end

  test "words no reply may contain, and a budget over the whole scenario" do
    turns = [ turn(reply: "There is one at Via Segreta 7.", tools: %w[search_records search_records]), turn(reply: "Done.", tools: %w[mark_done], applied: 1, seconds: 70) ]

    assert_equal [ "reply_excludes: a reply mentions Segreta" ], check([ { "reply_excludes" => [ "Segreta", "15:45" ] } ], turns)
    assert_equal [ "budget: 3 tool calls > 2, 71s > 60s" ], check([ { "budget" => { "tool_calls" => 2, "seconds" => 60 } } ], turns)
    big = [ AssistantEval::Runner::Turn.new(said: "hi", tools: [], reply: "Done.", seconds: 1, max_step_input: 11_800, applied: 1) ]
    assert_equal [ "budget: a step sent 11800 tokens > 11000" ], check([ { "budget" => { "tokens_per_step" => 11_000 } } ], big)
    assert_empty check([ { "budget" => { "tool_calls" => 3 } } ], turns)
  end
end
