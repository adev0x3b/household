# frozen_string_literal: true

require "test_helper"

# bin/provision end to end, with a machine that answers: the first run, a
# later run, one destination by name, the flags.
class Provision::WizardTest < ActiveSupport::TestCase
  include ProvisionFakes

  setup do
    @dir = Dir.mktmpdir
    @home = File.join(@dir, "home")
    FileUtils.mkdir_p(File.join(@home, ".ssh"))
    @config = File.join(@home, ".config", "household")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "--help, and an option it doesn't know" do
    shell = Shell.new(home: @home)
    assert_equal 0, wizard(%w[--help], shell: shell, root: checkout).run
    assert_includes shell.printed, "bin/provision status"
    assert_equal 1, wizard(%w[--what], shell: shell, root: checkout).run
    assert_match(/unknown option: --what/, shell.warnings)
  end

  test "status, or a destination, before anything says to run bin/provision" do
    shell = Shell.new(home: @home)
    assert_equal 1, wizard(%w[status], shell: shell, root: checkout).run
    assert_match(/nothing is set up here yet/, shell.warnings)
    assert_equal 1, wizard(%w[production], shell: shell, root: checkout).run
    assert_equal 2, shell.warnings.scan("nothing is set up here yet").size
  end

  test "a later run shows what runs and, with --yes, quits; only the four destinations are destinations" do
    root = checkout
    File.write(File.join(root, ".kamal", "env"), "DEPLOY_HOST=box.example\nGITHUB_REPOSITORY=owner/household\nPRODUCTION_HOST=example.com\nSTAGING_HOST=staging.example.com\n")
    installation(root).write_destination("staging", "UPLOADS" => "on")
    shell = Shell.new(home: @home)
    assert_equal 0, wizard(%w[--yes], shell: shell, root: root).run
    assert_includes shell.printed, "What runs here"
    assert_match(/staging\s+staging\.example\.com\s+✓/, shell.printed)
    assert_not shell.ran?(/gh workflow run/)

    assert_equal 1, wizard(%w[home], shell: shell, root: root).run
    assert_match(/home is not a destination/, shell.warnings)
  end

  test "the first run: .kamal/env asked and written, the machine done, each destination offered" do
    root = checkout
    answers = machine_answers.merge(/\Agh repo view --json nameWithOwner/ => "owner/household", /\Atimedatectl/ => "Europe/Rome")
    shell = Shell.new(home: @home, answers: answers)
    prompt = prompt_with("", "", "", "", "example.com", "", "", "y", "", "", "", "staging", "n")
    assert_equal 0, wizard([], shell: shell, prompt: prompt, root: root).run

    env = installation(root).kamal_env
    assert_equal [ "box.example", "owner", "owner/household", "example.com", "staging.example.com", "dev.example.com", "demo.example.com", nil, "Europe/Rome" ],
                 env.values_at("DEPLOY_HOST", "KAMAL_REGISTRY_USERNAME", "GITHUB_REPOSITORY", "PRODUCTION_HOST", "STAGING_HOST", "DEV_HOST", "DEMO_HOST", "MOUNT_PATH", "TIME_ZONE")
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --body box.example"
    assert shell.ran?(/gh secret set STAGING_POSTGRES_PASSWORD --repo owner\/household --env staging/)
    assert_not shell.ran?(/gh secret set PRODUCTION_POSTGRES_PASSWORD/), "only the destinations named run here"
    assert_not shell.ran?(/gh workflow run/)
  end

  test "a second machine's first run starts from the repository's variables, and leaves a destination that runs elsewhere to a move" do
    root = checkout
    shell = Shell.new(home: @home, answers: second_machine_answers)
    prompt = prompt_with("", "", "", "", "", "", "", "", "", "", "", "demo", "n")
    assert_equal 1, wizard([], shell: shell, prompt: prompt, root: root).run

    env = installation(root).kamal_env
    assert_equal %w[box.example example.com staging.example.com dev.example.com demo.example.com Europe/Rome],
                 env.values_at("DEPLOY_HOST", "PRODUCTION_HOST", "STAGING_HOST", "DEV_HOST", "DEMO_HOST", "TIME_ZONE")
    assert_match "demo runs on first.example: left alone here (bin/provision move demo", shell.warnings
    assert_not shell.ran?(/gh variable set DEPLOY_HOST/)
  end

  test "move on a machine new to the installation: .kamal/env from the repository's variables first" do
    root = checkout
    shell = Shell.new(home: @home, answers: second_machine_answers)
    moved = []
    stand_in = Object.new.tap { _1.define_singleton_method(:run!) { true } }
    swapping(Provision::Pipeline::Move, :new, ->(name, **) { moved << name; stand_in }) do
      assert_equal 0, wizard(%w[move demo], shell: shell, prompt: prompt_with("", "", "", "", "", "", "", "", "", "", ""), root: root).run
    end
    assert_equal %w[demo], moved
    assert_equal "box.example", installation(root).kamal_env["DEPLOY_HOST"]
    assert_equal "owner/public", installation(root).kamal_env["SOURCE_REPOSITORY"], "a private pipeline stays one"
  end

  test "every run first makes each destination's file say where its environment says it runs" do
    root = pipeline_root(@dir)
    installation(root).write_destination("demo", "DEPLOY_HOST" => "box.example", "UPLOADS" => "off")
    answers = machine_answers.merge(/\Agh variable list --repo owner\/household --env demo --json/ => '[{"name":"DEPLOY_HOST","value":"other.example"}]')
    shell = Shell.new(home: @home, answers: answers)
    wizard(%w[status], shell: shell, root: root).run

    assert_equal({ "DEPLOY_HOST" => "other.example", "UPLOADS" => "off" }, installation(root).destination("demo"))
    assert_includes shell.printed, "demo runs on other.example"
  end

  test "installation: .kamal/env asked again and the repository's variables set, a dropped name taken away, nothing deployed" do
    root = checkout
    File.write(File.join(root, ".kamal", "env"), "DEPLOY_HOST=box.example\nKAMAL_REGISTRY_USERNAME=owner\nGITHUB_REPOSITORY=owner/household\nPRODUCTION_HOST=example.com\nSTAGING_HOST=staging.example.com\nDEV_HOST=dev.example.com\nMOUNT_PATH=/love\n")
    installation(root).hosted = %w[production staging]
    shell = Shell.new(home: @home, answers: machine_answers)
    prompt = prompt_with("", "", "", "", "", "", "", "n", "/", "")
    assert_equal 0, wizard(%w[installation], shell: shell, prompt: prompt, root: root).run

    assert_nil installation(root).kamal_env["MOUNT_PATH"], "the root: no line"
    assert_includes shell.commands, "gh variable delete MOUNT_PATH --repo owner/household"
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --env staging --body box.example"
    assert_not shell.ran?(/gh workflow run|ssh-keygen -q|useradd/)
    assert_includes shell.printed, "next restart"
  end

  private

  def second_machine_answers
    variables = '[{"name":"DEPLOY_HOST","value":"first.example"},{"name":"PRODUCTION_HOST","value":"example.com"},{"name":"STAGING_HOST","value":"staging.example.com"},{"name":"DEV_HOST","value":"dev.example.com"},{"name":"DEMO_HOST","value":"demo.example.com"},{"name":"TIME_ZONE","value":"Europe/Rome"},{"name":"SOURCE_REPOSITORY","value":"owner/public"}]'
    machine_answers.merge(/\Agh repo view --json nameWithOwner/ => "owner/household", /\Agh variable list --repo owner\/household --json name,value\z/ => variables, /\Atimedatectl/ => "UTC")
  end

  def checkout
    root = File.join(@dir, "checkout")
    FileUtils.mkdir_p(File.join(root, ".kamal"))
    File.write(File.join(root, ".kamal", "env.example"), "# What config/deploy.yml needs.\n")
    root
  end

  def installation(root) = Provision::Installation.new(config_dir: @config, root: root)

  def wizard(argv, shell:, root:, prompt: prompt_with(assume_defaults: true))
    Provision::Wizard.new(argv, shell: shell, prompt: prompt, installation: installation(root), root: root)
  end
end
