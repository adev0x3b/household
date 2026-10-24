# frozen_string_literal: true

require "test_helper"
require "yaml"

# A destination brought to this machine from the one it runs on: the old
# machine reached and trusted by its recorded key, the data carried where
# it is kept, the version the old copy served deployed here, the old copy
# removed, and the old one started again when the new one doesn't come up.
class Provision::MoveTest < ActiveSupport::TestCase
  include ProvisionFakes

  SHA = "82e1df8abc0123456789abcdef0123456789abcd"
  OLD = "old.example"

  setup do
    @dir = Dir.mktmpdir
    @root = pipeline_root(@dir)
    @home = File.join(@dir, "home")
    FileUtils.mkdir_p(File.join(@home, ".ssh"))
    File.write(File.join(@home, ".ssh", "id_ed25519.pub"), "ssh-ed25519 AAAAmine me@box\n")
    @installation = Provision::Installation.new(config_dir: File.join(@home, ".config", "household"), root: @root)
    @runs = 0
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "the demo: started fresh here with the version it served there, seeded, then removed there with its volumes kept" do
    shell = Shell.new(home: @home, answers: answers("demo"))
    move("demo", shell, prompt_with("", "y")).run!

    assert_includes shell.commands, "ssh -o BatchMode=yes deploy@#{OLD} true"
    known = shell.calls.find { _1.argv.join(" ").include?("cat >> ") && _1.argv.join(" ").include?("known_hosts") }
    assert_equal "#{OLD} ssh-ed25519 AAAAold\n", known.options[:stdin], "the old machine trusted by the key the workflow recorded"
    assert_includes shell.commands, "gh variable set DEPLOY_HOST --repo owner/household --env demo --body box.example"
    assert shell.ran?(/\Assh-keygen -q -t ed25519/), "a new CI key for what runs here"
    assert_includes shell.commands, "gh workflow run deploy.yml --repo owner/household --ref main -f action=deploy -f destination=demo -f reason=bin/provision: deploy demo -f version=#{SHA}"
    assert_includes shell.commands, "docker exec household-web-demo-#{SHA} bin/rails demo:seed"
    assert_not shell.ran?(/tar -C/), "nothing carried"
    assert_not shell.ran?(/app stop/), "the old copy serves until the new one does"
    assert_includes shell.commands, "env DEPLOY_HOST=#{OLD} #{@root}/bin/kamal app remove -d demo"
    assert_includes shell.commands, "env DEPLOY_HOST=#{OLD} #{@root}/bin/kamal accessory remove db -y -d demo"
    assert_includes shell.printed, "docker volume rm household_demo_storage household_demo_secrets household_demo_db"
    assert_includes shell.printed, "demo.example.com → http://127.0.0.1:8080 on this machine's tunnel, taken off #{OLD}'s"
    assert_equal %w[demo], @installation.hosted
    assert_equal "box.example", @installation.destination("demo")["DEPLOY_HOST"]
  end

  test "the settings start from the environment's, and the keys GitHub holds stay there" do
    shell = Shell.new(home: @home, answers: answers("demo"))
    move("demo", shell, prompt_with("", "y")).run!

    settings = @installation.destination("demo")
    assert_equal %w[768MB anthropic off], settings.values_at("WEB_MEMORY", "ASSISTANT_PROVIDER", "UPLOADS")
    assert_not shell.ran?(/gh secret delete (ANTHROPIC_API_KEY|DEMO_PASSWORD) .* --env demo/)
    assert_not shell.ran?(/gh secret set DEMO_PASSWORD/), "not the catalogue's password over the one GitHub has"
    assert_not shell.ran?(/gh variable set WEB_MEMORY .* --env demo/), "already so"
  end

  test "staging: stopped there, its volumes carried, its database given this machine's password, deployed here, no new account" do
    shell = Shell.new(home: @home, answers: answers("staging"))
    move("staging", shell, prompt_with("y", "", "y")).run!

    password = File.read(@installation.postgres_password_file("staging"))
    reset = shell.calls.find { _1.argv.join(" ").include?("postgres --single") }
    assert_equal %w[docker run --rm -i -v household_staging_db:/var/lib/postgresql/data postgres:16 postgres --single -D /var/lib/postgresql/data household_production], reset.argv
    assert_equal "ALTER ROLE household PASSWORD '#{password}';\n", reset.options[:stdin]
    assert_not shell.ran?(/docker inspect/), "the old machine's password never leaves it"
    stop = shell.commands.index("env DEPLOY_HOST=#{OLD} #{@root}/bin/kamal accessory stop db -d staging")
    copies = shell.commands.each_index.select { shell.commands[_1].include?("/from:ro") }
    deploy = shell.commands.index { _1.start_with?("gh workflow run deploy.yml") }
    assert_equal 3, copies.size
    assert_operator stop, :<, copies.first, "stopped before the copy"
    assert_operator copies.last, :<, shell.calls.index(reset), "the password set on the copy"
    assert_operator shell.calls.index(reset), :<, deploy, "before the deploy connects"
    copy = Shellwords.split(shell.calls.find { _1.argv.join(" ").include?("/from:ro") }.argv.last)
    assert_equal [ "ssh", "-o", "BatchMode=yes", "deploy@#{OLD}", "docker run --rm -v household_staging_storage:/from:ro alpine:3.22 tar -C /from -cf - .", "|",
                   "docker", "run", "--rm", "-i", "-v", "household_staging_storage:/to", "alpine:3.22", "tar", "-C", "/to", "-xpf", "-" ], copy
    assert_not shell.ran?(/setup:code|admin:create|demo:seed/)
    assert_match "production doesn't run here", shell.warnings
  end

  test "a new copy that doesn't come up: the old one starts again, and the error says so" do
    shell = Shell.new(home: @home, answers: answers("staging").merge(/\Agh run watch/ => :fail))
    assert_raises(Provision::Stop) { move("staging", shell, prompt_with("y", "", "y")).run! }

    assert_includes shell.commands, "env DEPLOY_HOST=#{OLD} #{@root}/bin/kamal accessory start db -d staging"
    assert_includes shell.commands, "env DEPLOY_HOST=#{OLD} #{@root}/bin/kamal app start -d staging"
    assert_match "staging starts again on #{OLD}", shell.warnings
    assert_not shell.ran?(/app remove/)
  end

  test "what stops a move before it changes anything: already here, apart from its partner, the old machine out of reach" do
    shell = Shell.new(home: @home, answers: answers("demo", from: "box.example"))
    assert_match(/runs on this machine already.*deploy a version to a destination/, assert_raises(Provision::Stop) { move("demo", shell, prompt_with).run! }.message)

    shell = Shell.new(home: @home, answers: answers("production"))
    assert_raises(Provision::Stop) { move("production", shell, prompt_with("n")).run! }
    assert_not shell.ran?(/gh variable set|ssh-keygen -q/)

    shell = Shell.new(home: @home, answers: answers("demo").merge(/\Assh -o BatchMode=yes deploy@old\.example true/ => :fail))
    error = assert_raises(Provision::Stop) { move("demo", shell, prompt_with).run! }
    assert_includes error.message, %(echo 'from="100.64.0.0/10,fd7a:115c:a1e0::/48" ssh-ed25519 AAAAmine me@box' | sudo tee -a ~deploy/.ssh/authorized_keys)
    assert_not shell.ran?(/gh variable set|ssh-keygen -q/)
  end

  test "what keeps the proxy from coming up here stops a move before it changes anything: the port taken, a proxy left stopped" do
    shell = Shell.new(home: @home, answers: answers("demo").merge(/\Ass -Hltn/ => "LISTEN 0 4096 127.0.0.1:8080 0.0.0.0:*"))
    assert_includes assert_raises(Provision::Stop) { move("demo", shell, prompt_with).run! }.message, "holds port 8080"
    assert_not shell.ran?(/ssh -o BatchMode=yes|gh variable set|ssh-keygen -q/)

    stopped = "kamal-proxy\tbasecamp/kamal-proxy:v0.9.2\tCreated\tcreated\t\t\t\t\t"
    shell = Shell.new(home: @home, answers: answers("demo").merge(/\Adocker ps -a/ => stopped))
    assert_includes assert_raises(Provision::Stop) { move("demo", shell, prompt_with).run! }.message, "docker rm kamal-proxy"
  end

  test "a proxy already running here is the destinations' own: the port it holds is no obstacle" do
    here = answers("demo")
    running = "kamal-proxy\tbasecamp/kamal-proxy:v0.9.2\tUp 2 days\trunning\t\t\t\t\t\n#{here.fetch(/\Adocker ps -a/)}"
    shell = Shell.new(home: @home, answers: here.merge(/\Adocker ps -a/ => running, /\Ass -Hltn/ => "LISTEN 0 4096 127.0.0.1:8080"))
    move("demo", shell, prompt_with("", "y")).run!
    assert_not shell.ran?(/\Ass -Hltn/)
  end

  test "volumes left here from before stop a fresh move, naming them" do
    shell = Shell.new(home: @home, answers: answers("demo").merge(/\Adocker volume ls -q/ => "household_demo_db\nother"))
    error = assert_raises(Provision::Stop) { move("demo", shell, prompt_with("")).run! }
    assert_includes error.message, "docker volume rm household_demo_db"
  end

  private

  def move(name, shell, prompt)
    github = Provision::Pipeline::Github.new(shell, repo: "owner/household")
    Provision::Pipeline::Move.new(name, installation: @installation, shell: shell, prompt: prompt, github: github, docker: Provision::Docker.new(shell), root: @root)
  end

  # The old machine runs the destination; GitHub names it; this machine has everything a machine needs.
  def answers(name, from: OLD)
    prefix = name == "production" ? "household" : "household_#{name}"
    config = { volume_args: [ "--volume", "#{prefix}_storage:/rails/storage", "--volume", "#{prefix}_secrets:/rails/secrets" ],
               accessories: { "db" => { "service" => "household-#{name}-db", "image" => "postgres:16", "volumes" => [ "#{prefix}_db:/var/lib/postgresql/data" ] } } }
    machine_answers(keys: [], secrets: %w[ANTHROPIC_API_KEY DEMO_PASSWORD]).merge(
      %r{\Agh api repos/owner/household/environments/\w+\z} => "{}",
      /\Agh variable list --repo owner\/household --env #{name} --json/ => %([{"name":"DEPLOY_HOST","value":"#{from}"},{"name":"DEPLOY_KNOWN_HOSTS","value":"#{from} ssh-ed25519 AAAAold"},) +
                                                                            '{"name":"WEB_MEMORY","value":"768MB"},{"name":"ASSISTANT_PROVIDER","value":"anthropic"}]',
      /\Agh variable list --repo owner\/household --env \w+ --json/ => '[{"name":"DEPLOY_HOST","value":"elsewhere.example"}]',
      /\Agh variable list --repo owner\/household --json name,value\z/ => '[{"name":"DEPLOY_HOST","value":"old.example"}]',
      %r{\Agh api repos/owner/household/actions/runners} => "",
      /\Agh run list .* --workflow deploy.yml/ => ->(_argv) { (100 + ((@runs += 1) / 2)).to_s },
      /\Agit -C .* merge-base --is-ancestor/ => "",
      %r{bin/kamal config -d} => YAML.dump(config),
      /\Assh -o BatchMode=yes deploy@#{Regexp.escape(from)} docker ps -a/ => "household-web-#{name}-#{SHA}\tghcr.io/owner/household:#{SHA}\tUp 2 days (healthy)\trunning\thousehold\t#{name}\tweb\t\t",
      /\Adocker ps -a/ => "household-web-#{name}-#{SHA}\tghcr.io/owner/household:#{SHA}\tUp 1 minute (healthy)\trunning\thousehold\t#{name}\tweb\t\t",
      /\Adocker volume ls -q/ => ""
    )
  end
end
