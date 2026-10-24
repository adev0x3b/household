# frozen_string_literal: true

require "test_helper"

# A destination's file: NAME=value lines Dotenv, Docker Compose and a shell
# read alike, written readable by its owner alone.
class Provision::EnvFileTest < ActiveSupport::TestCase
  test "parses what a person or the wizard wrote" do
    text = <<~ENV
      # the demo
      DESTINATION=demo
      export PORT=8090
      APP_HOST = household.home   # with spaces around
      FILES_QUOTA=64MB # a trailing comment
      ANTHROPIC_API_KEY="sk-ant-with \\"quotes\\" and a \\$"
      TITLE='single quoted # not a comment'

      EMPTY=
    ENV
    assert_equal({ "DESTINATION" => "demo", "PORT" => "8090", "APP_HOST" => "household.home", "FILES_QUOTA" => "64MB",
                   "ANTHROPIC_API_KEY" => 'sk-ant-with "quotes" and a $', "TITLE" => "single quoted # not a comment", "EMPTY" => "" },
                 Provision::EnvFile.parse(text))
  end

  test "renders bare what every reader takes bare, quoted otherwise, and comes back the same" do
    pairs = { "PLAIN" => "on", "URL" => "http://host.docker.internal:11434", "LIST" => "alex.demo,sam.demo", "SPACED" => "a value with spaces",
              "QUOTED" => 'say "hi"', "DOLLAR" => "costs $5", "HASH" => "a # not a comment", "TICKS" => "run `date`", "EMPTY" => "" }
    text = Provision::EnvFile.render(pairs, header: "the demo's settings\nwritten by bin/provision")
    assert text.start_with?("# the demo's settings\n# written by bin/provision\n\n")
    assert_includes text, "PLAIN=on\n"
    assert_includes text, "URL=http://host.docker.internal:11434\n"
    assert_includes text, %(SPACED="a value with spaces"\n)
    assert_includes text, %(QUOTED="say \\"hi\\""\n)
    assert_includes text, "EMPTY=\n"
    assert_equal pairs, Provision::EnvFile.parse(text)
  end

  test "a shell reading the file takes every value as written, running nothing" do
    pairs = { "QUOTED" => 'say "hi"', "DOLLAR" => "costs $5", "TICKS" => "run `date`", "SLASH" => 'C:\\path' }
    Dir.mktmpdir do |dir|
      path = File.join(dir, "demo.env")
      Provision::EnvFile.write(path, pairs)
      script = '. "$1"; printf "%s|%s|%s|%s" "$QUOTED" "$DOLLAR" "$TICKS" "$SLASH"'
      output, status = Open3.capture2("sh", "-c", script, "sh", path)
      assert_predicate status, :success?
      assert_equal pairs.values.join("|"), output
    end
  end

  test "a value with a line break has no safe spelling" do
    assert_raises(ArgumentError) { Provision::EnvFile.render("KEY" => "two\nlines") }
  end

  test "writes the file readable by its owner alone, in a directory of its own" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "household", "demo.env")
      Provision::EnvFile.write(path, { "DESTINATION" => "demo" }, header: "demo")
      assert_equal "100600", File.stat(path).mode.to_s(8)
      assert_equal "40700", File.stat(File.dirname(path)).mode.to_s(8)
      assert_equal({ "DESTINATION" => "demo" }, Provision::EnvFile.read(path))
      assert_equal({}, Provision::EnvFile.read(File.join(dir, "none.env")))
    end
  end
end
