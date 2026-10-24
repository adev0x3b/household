# frozen_string_literal: true

require "test_helper"

# A pipeline's machine, as bin/provision machine makes it: the CI key
# made once and put where it belongs, the passwords made once, the
# repository's variables, the notes — safe to run again.
class Provision::MachineTest < ActiveSupport::TestCase
  include ProvisionFakes

  CI_LINE = 'restrict,from="100.64.0.0/10,fd7a:115c:a1e0::/48" ssh-ed25519 AAAAci household-ci'
  MY_KEY = "ssh-ed25519 AAAAmine me@box"

  setup do
    @dir = Dir.mktmpdir
    @root = pipeline_root(@dir)
    @home = File.join(@dir, "home")
    FileUtils.mkdir_p(File.join(@home, ".ssh"))
    File.write(File.join(@home, ".ssh", "id_ed25519.pub"), "#{MY_KEY}\n")
    @installation = Provision::Installation.new(config_dir: File.join(@home, ".config", "household"), root: @root)
    FileUtils.mkdir_p(@installation.config_dir)
    @installed = {}
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "everything in place: no new key, the passwords kept, the variables set, the notes printed" do
    %w[production staging demo dev].each { File.write(@installation.postgres_password_file(_1), "keep-#{_1}") }
    shell = Shell.new(home: @home, answers: machine_answers(keys: [ CI_LINE, %(from="x" #{MY_KEY}) ], installed: @installed))
    machine(shell).run!

    assert_not shell.ran?(/ssh-keygen -q/)
    assert_not shell.ran?(/gh secret set DEPLOY_SSH_KEY/)
    assert_includes shell.printed, "the CI key is in place"
    assert_equal "keep-demo", File.read(@installation.postgres_password_file("demo"))
    password = shell.calls.find { _1.argv.join(" ").start_with?("gh secret set DEMO_POSTGRES_PASSWORD --repo owner/household --env demo") }
    assert_equal "keep-demo", password.options[:stdin]
    assert_includes shell.commands, "gh secret delete DEMO_POSTGRES_PASSWORD --repo owner/household"
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --body box.example"
    assert_includes shell.commands, "gh variable set DEMO_HOST --repo owner/household --body demo.example.com"
    assert_includes shell.commands, "gh variable set TIME_ZONE --repo owner/household --body Europe/Rome"
    assert_includes shell.commands, "gh variable set DEPLOY_KNOWN_HOSTS --repo owner/household --body box.example ssh-ed25519 AAAAhost"
    known = shell.calls.find { _1.argv.join(" ").include?("cat >> ") && _1.argv.join(" ").include?("known_hosts") }
    assert_equal "box.example ssh-ed25519 AAAAhost\n", known.options[:stdin]
    assert shell.calls.find { _1.argv.first == "install" && _1.argv.last == "/home/deploy/.ssh/authorized_keys" }.options[:sudo]
    assert_equal "#{CI_LINE}\nfrom=\"x\" #{MY_KEY}\n", @installed[:authorized_keys]
    assert_includes shell.printed, "demo.example.com → http://127.0.0.1:8080, nothing in front"
    assert_includes shell.printed, '"hosts": { "box": "100.64.0.9" }'
  end

  test "a missing CI key is made: its private half in every environment, its public half for the tailnet, the file shredded" do
    shell = Shell.new(home: @home, answers: machine_answers(keys: [], secrets: [], installed: @installed))
    machine(shell).run!

    assert shell.ran?(/ssh-keygen -q -t ed25519 -N  -C household-ci -f/)
    %w[production staging demo dev].each do |destination|
      call = shell.calls.find { _1.argv.join(" ") == "gh secret set DEPLOY_SSH_KEY --repo owner/household --env #{destination}" }
      assert_equal "PRIVATE KEY\n", call.options[:stdin], destination
    end
    assert_includes shell.commands, "gh secret delete DEPLOY_SSH_KEY --repo owner/household"
    assert shell.ran?(/\Ashred -u /)
    assert_equal "#{CI_LINE}\nfrom=\"100.64.0.0/10,fd7a:115c:a1e0::/48,127.0.0.1,::1\" #{MY_KEY}\n", @installed[:authorized_keys]
    %w[production staging demo dev].each do |destination|
      file = @installation.postgres_password_file(destination)
      assert_match(/\A\h{48}\z/, File.read(file), "no newline, 48 hex characters")
      assert_equal "100600", File.stat(file).mode.to_s(8)
    end
  end

  test "--rotate-ci-key makes a new one even with one in place" do
    shell = Shell.new(home: @home, answers: machine_answers(keys: [ CI_LINE ], installed: @installed))
    machine(shell, rotate: true).run!
    assert shell.ran?(/ssh-keygen -q/)
    assert_equal 1, @installed[:authorized_keys].scan("household-ci").size
  end

  test "without environments the secrets are the repository's, and the warning says so" do
    answers = machine_answers(installed: @installed).merge(%r{\Agh api --method PUT repos/owner/household/environments/} => :fail)
    shell = Shell.new(home: @home, answers: answers)
    machine(shell).run!
    assert_includes shell.commands, "gh secret set DEPLOY_SSH_KEY --repo owner/household"
    assert_not shell.ran?(/gh secret set DEPLOY_SSH_KEY --repo owner\/household --env/)
    assert_match(/no environments/, shell.warnings)
  end

  test "what the machine lacks stops it, saying what" do
    shell = Shell.new(home: @home, answers: machine_answers.merge(/\Atailscale status --json/ => ""))
    error = assert_raises(Provision::Stop) { machine(shell).run! }
    assert_match(/Tailscale isn't up/, error.message)
  end

  test "a destination that runs on another machine is left alone, and with nothing else named nothing is done" do
    answers = machine_answers(installed: @installed).merge(
      /\Agh variable list --repo owner\/household --json name,value\z/ => '[{"name":"DEPLOY_HOST","value":"box.example"}]',
      /\Agh variable list --repo owner\/household --env demo --json/ => '[{"name":"DEPLOY_HOST","value":"other.example"}]'
    )
    shell = Shell.new(home: @home, answers: answers)
    @installation.hosted = %w[production demo]
    machine(shell, destinations: %w[production demo]).run!

    assert_match "demo runs on other.example: left alone here (bin/provision move demo", shell.warnings
    assert_not shell.ran?(/--env demo --body box.example/)
    assert_not File.exist?(@installation.postgres_password_file("demo"))
    assert_equal %w[production], @installation.hosted, "the list forgets what moved away"

    shell = Shell.new(home: @home, answers: answers)
    error = assert_raises(Provision::Stop) { machine(shell, destinations: %w[demo]).run! }
    assert_match(/nothing to set up here/, error.message)
    assert_not shell.ran?(/useradd|gh secret set/)
  end

  test "a second machine: its name and host key on its destinations' environments alone, its CI key and password for them alone, each file naming it" do
    answers = machine_answers(installed: @installed).merge(/\Agh variable list --repo owner\/household --json name,value\z/ => '[{"name":"DEPLOY_HOST","value":"first.example"}]')
    shell = Shell.new(home: @home, answers: answers)
    machine(shell, destinations: %w[demo], claiming: %w[demo]).run!

    assert_not_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --body box.example", "the repository's level stays the first machine's"
    assert_not shell.ran?(/gh variable set DEPLOY_KNOWN_HOSTS --repo owner\/household --body/)
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --env demo --body box.example"
    assert_includes shell.commands, "gh variable set DEPLOY_KNOWN_HOSTS --repo owner/household --env demo --body box.example ssh-ed25519 AAAAhost"
    assert_includes shell.commands, "gh variable set PRODUCTION_HOST --repo owner/household --body example.com", "the installation's names are everyone's"
    assert_equal [ "gh secret set DEPLOY_SSH_KEY --repo owner/household --env demo" ], shell.commands.grep(/gh secret set DEPLOY_SSH_KEY/)
    assert_equal([ "demo" ], %w[production staging demo dev].select { File.exist?(@installation.postgres_password_file(_1)) })
    assert_equal "box.example", @installation.destination("demo")["DEPLOY_HOST"]
    assert_equal %w[demo], @installation.hosted
    assert_includes shell.printed, "DEPLOY_HOST (demo's environment)"
    assert_includes shell.printed, '"acls":   { "action": "accept", "src": ["tag:ci"], "dst": ["box:22"] }'
    assert_includes shell.printed, "demo.example.com → http://127.0.0.1:8080"
    assert_not_includes shell.printed, "example.com → http://127.0.0.1:8080;", "only this machine's destinations move to its tunnel"
  end

  test "the first machine: the repository's level and its destinations' environments both" do
    shell = Shell.new(home: @home, answers: machine_answers(installed: @installed))
    machine(shell).run!
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --body box.example"
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --env production --body box.example"
    assert_includes shell.commands, "gh variable set DEPLOY_KNOWN_HOSTS --repo owner/household --env dev --body box.example ssh-ed25519 AAAAhost"
    assert_equal %w[production staging demo dev], @installation.hosted
  end

  private

  def machine(shell, rotate: false, destinations: %w[production staging demo dev], claiming: [])
    github = Provision::Pipeline::Github.new(shell, repo: "owner/household")
    Provision::Pipeline::Machine.new(installation: @installation, shell: shell, github: github, docker: Provision::Docker.new(shell),
                                     destinations: destinations, rotate_ci_key: rotate, claiming: claiming)
  end
end
