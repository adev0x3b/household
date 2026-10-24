# frozen_string_literal: true

require "test_helper"

# What this machine holds for the pipeline: the destinations it runs, each
# one's file, .kamal/env.
class Provision::InstallationTest < ActiveSupport::TestCase
  test "a destination's file: written readable by its owner alone, read back" do
    with_installation do |installation, _root|
      assert_not installation.destination?("demo")
      installation.write_destination("demo", "DESTINATION" => "demo", "UPLOADS" => "off", "ANTHROPIC_API_KEY" => "sk-ant x")
      assert installation.destination?("demo")
      assert_equal "100600", File.stat(installation.destination_file("demo")).mode.to_s(8)
      assert_equal({ "DESTINATION" => "demo", "UPLOADS" => "off", "ANTHROPIC_API_KEY" => "sk-ant x" }, installation.destination("demo"))
    end
  end

  test ".kamal/env: the names config/deploy.yml reads, the empty ones left out, env.example's words on top" do
    with_installation do |installation, root|
      FileUtils.mkdir_p(File.join(root, ".kamal"))
      File.write(File.join(root, ".kamal", "env.example"), "# What config/deploy.yml needs about this installation.\n# Copy to .kamal/env.\n\nDEPLOY_HOST=server\n")
      installation.write_kamal_env("DEPLOY_HOST" => "box.example", "GITHUB_REPOSITORY" => "owner/household", "DEMO_HOST" => "", "NOT_A_NAME" => "x")
      text = File.read(installation.kamal_env_file)
      assert text.start_with?("# What config/deploy.yml needs about this installation.\n# Copy to .kamal/env.\n")
      assert_equal({ "DEPLOY_HOST" => "box.example", "GITHUB_REPOSITORY" => "owner/household" }, installation.kamal_env)
      assert installation.kamal_env?("DEPLOY_HOST")
      assert_not installation.kamal_env?("DEMO_HOST")
    end
  end

  test "which destinations run here, and where each runs: its file's machine, else this one" do
    with_installation do |installation, root|
      assert_nil installation.hosted
      installation.hosted = %w[demo]
      assert_equal %w[demo], installation.hosted

      FileUtils.mkdir_p(File.join(root, ".kamal"))
      File.write(File.join(root, ".kamal", "env"), "DEPLOY_HOST=box.example\n")
      installation.write_destination("demo", "DEPLOY_HOST" => "other.example")
      installation.write_destination("production", "UPLOADS" => "on")
      assert_equal "box.example", installation.this_host
      assert_equal "other.example", installation.host_of("demo")
      assert_equal "box.example", installation.host_of("production")
      assert installation.remote?("demo")
      assert_not installation.remote?("production")
      assert_not installation.remote?("staging"), "no file: it runs here"
    end
  end

  private

  def with_installation
    Dir.mktmpdir do |dir|
      root = File.join(dir, "checkout")
      FileUtils.mkdir_p(root)
      yield Provision::Installation.new(config_dir: File.join(dir, "config", "household"), root: root), root
    end
  end
end
