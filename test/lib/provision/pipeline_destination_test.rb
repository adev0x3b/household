# frozen_string_literal: true

require "test_helper"

# A destination of the pipeline: its file mirrored to its GitHub
# environment, the Deploy workflow dispatched and followed, the first
# account made in the running container.
class Provision::PipelineDestinationTest < ActiveSupport::TestCase
  include ProvisionFakes

  SHA = "82e1df8abc0123456789abcdef0123456789abcd"

  setup do
    @dir = Dir.mktmpdir
    @root = pipeline_root(@dir)
    @installation = Provision::Installation.new(config_dir: File.join(@dir, "config"), root: @root)
    @runs = 0
    @answers = {
      %r{\Agh api repos/owner/household/environments/demo\z} => "{}",
      %r{\Agh api repos/owner/household/environments/production\z} => "{}",
      %r{\Agh api repos/owner/household/environments/dev\z} => "{}",
      /\Agh variable list --repo owner\/household --env demo --json/ => '[{"name":"UPLOADS","value":"off"},{"name":"ASSISTANT_MODEL","value":"old"}]',
      /\Agh variable list --repo owner\/household --env \w+ --json/ => "[]",
      /\Agh secret list --repo owner\/household --env demo/ => "GOOGLE_BOOKS_API_KEY",
      /\Agh secret list --repo owner\/household --env/ => "",
      /\Agh variable list --repo owner\/household --json name,value\z/ => '[{"name":"RUNS_ON","value":"[\"self-hosted\",\"zed\"]"}]',
      %r{\Agh api repos/owner/household/actions/runners} => "self-hosted,linux,zed",
      /\Agh run list .* --workflow ci.yml/ => SHA,
      # A run id a dispatch makes new: asked before (the one there was), then after (the one it started).
      /\Agh run list .* --workflow deploy.yml/ => ->(_argv) { (100 + ((@runs += 1) / 2)).to_s },
      /\Agit -C .* merge-base --is-ancestor/ => "",
      /\Adocker ps -a/ => "household-web-demo-#{SHA}\tghcr.io/owner/household:#{SHA}\tUp 1 minute (healthy)\trunning\thousehold\tdemo\tweb\t\t\n" \
                          "household-web-production-#{SHA}\tghcr.io/owner/household:#{SHA}\tUp 1 minute (healthy)\trunning\thousehold\tproduction\tweb\t\t\n"
    }
    @shell = Shell.new(answers: @answers)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "set up the demo: the file, the mirror reconciled, the Deploy workflow followed, the seed, the Cloudflare line" do
    destination("demo", prompt_with("y", "")).set_up!

    assert_equal "off", @installation.destination("demo")["UPLOADS"]
    commands = @shell.commands
    assert_not_includes commands, "gh variable set UPLOADS --repo owner/household --env demo --body off", "already off on GitHub"
    assert_includes commands, "gh variable set PICTURES --repo owner/household --env demo --body off"
    assert_includes commands, "gh variable set ASSISTANT_MODEL --repo owner/household --env demo --body qwen3:8b"
    assert_includes commands, "gh variable set OPEN_ACCOUNTS --repo owner/household --env demo --body #{Provision::Settings::DEMO_ACCOUNTS}"
    assert_includes commands, "gh secret delete GOOGLE_BOOKS_API_KEY --repo owner/household --env demo"
    secret = @shell.calls.find { _1.argv.join(" ").start_with?("gh secret set DEMO_PASSWORD") }
    assert_equal "demo-household", secret.options[:stdin]
    assert_not @shell.ran?(/gh secret set ANTHROPIC_API_KEY/)
    assert_includes commands, "gh workflow run deploy.yml --repo owner/household --ref main -f action=deploy -f destination=demo -f reason=bin/provision: deploy demo -f version=#{SHA}"
    assert_includes commands, "gh run watch 101 --repo owner/household --exit-status"
    assert_includes commands, "docker exec household-web-demo-#{SHA} bin/rails demo:seed"
    assert_includes @shell.printed, "demo.example.com → http://127.0.0.1:8080, nothing in front"
  end

  test "production: its name typed, a commit not on main refused, no runner online stops it before dispatching" do
    destination("production", prompt_with("y", "", "production", "n")).set_up!
    assert @shell.ran?(/gh workflow run deploy.yml .* -f destination=production -f reason=bin\/provision: deploy production -f version=#{SHA}/)
    assert_not @shell.ran?(/admin:create/), "the admin wasn't asked for"
    assert_includes @shell.commands, "docker exec household-web-production-#{SHA} bin/rails setup:code", "the setup page's code instead"

    @shell = Shell.new(answers: @answers)
    assert_raises(Provision::Stop) { destination("production", prompt_with("y", "", "nope")).set_up! }
    assert_not @shell.ran?(/gh workflow run/)

    @shell = Shell.new(answers: @answers.merge(/\Agit -C .* merge-base --is-ancestor/ => :fail))
    error = assert_raises(Provision::Stop) { destination("production", prompt_with("y", "", "production")).set_up! }
    assert_match(/not on main/, error.message)

    @shell = Shell.new(answers: @answers.merge(%r{\Agh api repos/owner/household/actions/runners} => ""))
    error = assert_raises(Provision::Stop) { destination("demo", prompt_with("y", "")).set_up! }
    assert_match(/no runner takes jobs/, error.message)
    assert_not @shell.ran?(/gh workflow run/)
  end

  test "without an environment on GitHub, the file alone and a warning; dev's first boot is a fresh preview of main" do
    @shell = Shell.new(answers: @answers.merge(%r{\Agh api repos/owner/household/environments/demo\z} => :fail))
    destination("demo", prompt_with("y", "")).set_up!
    assert_match(/no environment demo/, @shell.warnings)
    assert_not @shell.ran?(/gh variable set/)

    @shell = Shell.new(answers: @answers)
    destination("dev", prompt_with("y")).set_up!
    assert @shell.ran?(/gh workflow run deploy.yml --repo owner\/household --ref main -f action=preview -f destination=dev -f reason=bin\/provision: preview dev -f branch=main -f fresh=true/)
    assert_not @shell.ran?(/demo:seed/)
  end

  test "a settings change restarts a running destination through the workflow" do
    @installation.write_destination("demo", "UPLOADS" => "off")
    destination("demo", prompt_with("y")).change!
    assert @shell.ran?(/gh workflow run deploy.yml .* -f action=restart -f destination=demo/)
  end

  test "a destination on a machine of its own: seeded over SSH, its file keeping the machine" do
    @installation.write_destination("demo", "DEPLOY_HOST" => "other.example")
    @shell = Shell.new(answers: @answers.merge(/\Assh -o BatchMode=yes deploy@other.example docker ps/ => "household-web-demo-#{SHA}\tghcr.io/o/h:#{SHA}\tUp 1 minute (healthy)\trunning\thousehold\tdemo\tweb\t\t"))
    destination("demo", prompt_with("y", "")).set_up!
    assert_includes @shell.commands, "ssh -o BatchMode=yes deploy@other.example docker exec household-web-demo-#{SHA} bin/rails demo:seed"
    assert_equal "other.example", @installation.destination("demo")["DEPLOY_HOST"]
    assert_not @shell.ran?(/\Adocker exec/)
  end

  private

  def destination(name, prompt)
    github = Provision::Pipeline::Github.new(@shell, repo: "owner/household")
    Provision::Pipeline::Destination.new(name, installation: @installation, shell: @shell, prompt: prompt, github: github, docker: Provision::Docker.new(@shell), root: @root)
  end
end
