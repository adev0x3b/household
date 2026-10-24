# frozen_string_literal: true

require "test_helper"

# The wizard's questions: defaults on Enter, yes/no, a choice by name or
# number, a secret kept when nothing is typed, and --yes taking every
# default but what has none.
class Provision::PromptTest < ActiveSupport::TestCase
  include ProvisionFakes

  test "an answer, or the default on Enter, and a required one asked again" do
    prompt = prompt_with("", "typed", "", "", "at last")
    assert_equal "kept", prompt.ask("Q", default: "kept")
    assert_equal "typed", prompt.ask("Q", default: "kept")
    assert_equal "", prompt.ask("Q")
    assert_equal "at last", prompt.ask("Q", required: true)
  end

  test "yes or no, with the default on Enter" do
    prompt = prompt_with("", "n", "YES", "")
    assert prompt.yes?("Q", default: true)
    assert_not prompt.yes?("Q", default: true)
    assert prompt.yes?("Q", default: false)
    assert_not prompt.yes?("Q", default: false)
  end

  test "a choice by number, by name, or the default; anything else asked again" do
    prompt = prompt_with("2", "pipeline", "", "maybe", "1")
    assert_equal "pipeline", prompt.choose("Mode?", %w[local pipeline], default: "local")
    assert_equal "pipeline", prompt.choose("Mode?", %w[local pipeline], default: "local")
    assert_equal "local", prompt.choose("Mode?", %w[local pipeline], default: "local")
    assert_equal "local", prompt.choose("Mode?", %w[local pipeline], default: "local")
  end

  test "a secret typed, or kept, or required" do
    prompt = prompt_with("sk-new", "", "", "finally")
    assert_equal "sk-new", prompt.secret("Key")
    assert_equal "sk-old", prompt.secret("Key", default: "sk-old")
    assert_equal "finally", prompt.secret("Key", required: true)
  end

  test "--yes takes every default and asks only what has none" do
    prompt = prompt_with("household.home", "pw", assume_defaults: true)
    assert_equal "kept", prompt.ask("Q", default: "kept")
    assert prompt.yes?("Q", default: true)
    assert_equal "local", prompt.choose("Mode?", %w[local pipeline], default: "local")
    assert_equal "sk-old", prompt.secret("Key", default: "sk-old")
    assert_equal "household.home", prompt.ask("Address", required: true)
    assert_equal "pw", prompt.secret("Password", required: true)
  end
end
