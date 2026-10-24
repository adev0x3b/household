# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tempfile"
require "tmpdir"

module Provision
  module Pipeline
    # This machine made Kamal's host, one step at a time, safe to run again:
    # Docker; sshd, Tailscale and gh checked; each destination's GitHub
    # environment, main alone allowed; the deploy user Kamal logs in as; the CI key — its
    # private half in the environments of the destinations that run here,
    # its public half in deploy's authorized_keys, from the tailnet, for
    # commands only — and yours; the host key the workflow trusts; the
    # repository's variables; a database password per destination, made
    # once, in its environment alone; a fork's run waiting for approval; a
    # runner here warned about. What it can't do, the Tailscale and
    # Cloudflare consoles, it prints at the end.
    class Machine
      TAILNET = "100.64.0.0/10,fd7a:115c:a1e0::/48"
      KEY_COMMENT = "household-ci"

      # claiming: the destinations brought here from another machine
      # (bin/provision move); every other one is set up here only if it runs
      # here already, or nowhere yet.
      def initialize(installation:, shell:, github:, docker:, destinations:, rotate_ci_key: false, claiming: [])
        @installation = installation
        @shell = shell
        @github = github
        @docker = docker
        @destinations = destinations
        @rotate = rotate_ci_key
        @claiming = claiming
        @elsewhere = []
        @environments = false
      end

      def run!
        leave_what_runs_elsewhere!
        @docker.install!
        prerequisites!
        environments!
        deploy_user!
        keys!
        host_key!
        repository_variables!
        database_passwords!
        hosted_files!
        fork_approval!
        runner!
        notes
      end

      # The repository's variables alone, after .kamal/env changed (bin/provision installation).
      def variables!
        leave_what_runs_elsewhere!
        @environments = @destinations.all? { @github.environment?(_1) }
        host_key!
        repository_variables!
      end

      private

      # The Deploy workflow deploys a destination where its environment says,
      # so that is where it runs: a machine it has moved away from leaves it
      # alone, and a second run there can't take it back.
      def leave_what_runs_elsewhere!
        @elsewhere = @destinations.reject do |destination|
          @claiming.include?(destination) || [ nil, host ].include?(@github.deploy_host(destination))
        end
        @elsewhere.each do |destination|
          @shell.warn "#{destination} runs on #{@github.deploy_host(destination)}: left alone here (bin/provision move #{destination}, run on this machine, brings it here)"
        end
        @destinations -= @elsewhere
        raise Stop, "every destination named runs on another machine: nothing to set up here" if @destinations.empty?
      end

      def env = @installation.kamal_env
      def host = env.fetch("DEPLOY_HOST") { raise Stop, "DEPLOY_HOST isn't set in .kamal/env" }

      def prerequisites!
        @shell.say "What this needs: sshd, Tailscale, gh"
        unless @shell.ok?("systemctl", "is-active", "--quiet", "ssh") || @shell.ok?("systemctl", "is-active", "--quiet", "sshd")
          raise Stop, "sshd isn't running: sudo apt-get install openssh-server"
        end

        status = @shell.capture("tailscale", "status", "--json", allow_failure: true).to_s
        own = begin
          JSON.parse(status).dig("Self", "DNSName").to_s.chomp(".")
        rescue JSON::ParserError
          ""
        end
        raise Stop, "Tailscale isn't up: sudo tailscale up" if own.empty?

        @shell.warn "this machine is #{own} on the tailnet, config/deploy.yml says #{host}: make them agree" unless own == host
        raise Stop, "gh isn't signed in: gh auth login" unless @shell.ok?("gh", "auth", "status", as_me: true)
        raise Stop, "gh's account can't set #{@github.repo}'s secrets" unless @github.admin?

        @shell.tell "sshd, Tailscale (#{own}) and gh are ready"
      end

      # The deploy secrets live in each destination's environment, which only
      # main may use. GitHub Free gives environments to public
      # repositories alone: while this one is private they stay the
      # repository's, and running this again once it is public moves them.
      def environments!
        @shell.say "Each destination's GitHub environment: main only"
        @environments = @destinations.all? do |destination|
          @github.environment!(destination).tap { |made| @shell.tell "#{destination}: its secrets for main alone" if made }
        end
        return if @environments

        @shell.warn "GitHub has no environments for #{@github.repo} (GitHub Free: public repositories only). The deploy secrets stay the repository's, readable from any branch; run this again once it is public."
      end

      def deploy_user!
        @shell.say "The deploy user (Kamal's ssh user)"
        @shell.run("useradd", "--create-home", "--shell", "/bin/bash", "deploy", sudo: true) unless @shell.ok?("id", "deploy")
        @shell.run("usermod", "-aG", "docker", "deploy", sudo: true)
        # No password, and not locked either: sshd turns away a locked account even with a valid key (UsePAM).
        @shell.run("usermod", "-p", "*", "deploy", sudo: true)
        @shell.run("install", "-d", "-m", "700", "-o", "deploy", "-g", "deploy", File.join(deploy_home, ".ssh"), sudo: true)
      end

      def deploy_home = @deploy_home ||= @shell.capture("getent", "passwd", "deploy").split(":")[5]
      def keys_file = File.join(deploy_home, ".ssh", "authorized_keys")

      # The Deploy workflow's key: commands only, from the tailnet only, and
      # the private half in the environments of the destinations here, then
      # nowhere. Yours too, so bin/kamal works by hand from this machine.
      def keys!
        @shell.say "deploy's authorized_keys: the CI key, and yours"
        lines = @shell.capture("cat", keys_file, sudo: true, allow_failure: true).to_s.lines.map(&:chomp).reject(&:empty?)
        if @rotate || lines.none? { _1.end_with?(" #{KEY_COMMENT}") } || missing_in_an_environment?("DEPLOY_SSH_KEY")
          Dir.mktmpdir do |work|
            private_key = File.join(work, "ci")
            @shell.run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", KEY_COMMENT, "-f", private_key)
            put_secret("DEPLOY_SSH_KEY", File.read(private_key), @destinations)
            lines = lines.reject { _1.end_with?(" #{KEY_COMMENT}") } << %(restrict,from="#{TAILNET}" #{File.read("#{private_key}.pub").strip})
            @shell.run("shred", "-u", private_key)
          end
          @shell.tell "a new CI key: its private half is the DEPLOY_SSH_KEY secret, and nowhere else"
        else
          @shell.tell "the CI key is in place (--rotate-ci-key makes a new one)"
        end

        mine = Dir[File.join(@shell.my_home, ".ssh", "id_*.pub")]
        mine.each do |pub|
          key = File.read(pub).split[0, 2].join(" ")
          lines << %(from="#{TAILNET},127.0.0.1,::1" #{File.read(pub).strip}) unless lines.any? { _1.include?(key) }
        end
        @shell.warn "no ~/.ssh/id_*.pub to let you in as deploy (ssh-keygen -t ed25519, then run this again)" if mine.empty?

        Tempfile.create("authorized_keys") do |file|
          file.write(lines.join("\n") + "\n")
          file.flush
          @shell.run("install", "-m", "600", "-o", "deploy", "-g", "deploy", file.path, keys_file, sudo: true)
        end
        @shell.tell "deploy's authorized_keys: #{lines.size} keys"
      end

      # The host key the workflow must find, read from the file: no scan, no
      # trust on first use. Yours gets it too, for bin/kamal by hand, looked
      # up by the machine's name alone (HostKeyAlias: Kamal's net-ssh reads ~/.ssh/config).
      def host_key!
        @shell.say "The repository's settings for the Deploy workflow"
        key = @shell.capture("cat", "/etc/ssh/ssh_host_ed25519_key.pub").split[0, 2].join(" ")
        known_host = "#{host} #{key}"
        put_variable("DEPLOY_KNOWN_HOSTS", known_host)
        @shell.tell "DEPLOY_KNOWN_HOSTS: #{host}'s ed25519 key, #{where_variables_go}"
        KnownHosts.new(@shell).trust!(known_host)
      end

      # What config/deploy.yml reads from the environment, for the workflow:
      # the installation's names at the repository's level; this machine's
      # (DEPLOY_HOST, its host key) on the environments of the destinations
      # that run here, and at the repository's level only while this is the
      # machine the repository's level names (the first, or the only one).
      def repository_variables!
        %w[DEPLOY_HOST PRODUCTION_HOST STAGING_HOST DEV_HOST].each do |name|
          value = env[name].to_s
          raise Stop, "#{name} isn't set in .kamal/env" if value.empty?

          name == "DEPLOY_HOST" ? put_variable(name, value) : @github.variable_set(name, value)
        end
        @shell.tell "DEPLOY_HOST (#{where_variables_go}), PRODUCTION_HOST, STAGING_HOST, DEV_HOST: from .kamal/env"
        # A name .kamal/env has no value for (no demo, the root, UTC, the code
        # in this same repository) is taken away.
        %w[DEMO_HOST MOUNT_PATH TIME_ZONE SOURCE_REPOSITORY].each do |name|
          if env[name].to_s.empty?
            @github.variable_delete(name)
          else
            @github.variable_set(name, env[name])
            @shell.tell "#{name}: from .kamal/env"
          end
        end
      end

      # Each destination's database password: made once, kept here (bin/kamal
      # by hand reads it, .kamal/secrets.<destination>) and in that
      # destination's environment alone (CI). Never remade: the role's
      # password lives in the database volume from the first boot on.
      def database_passwords!
        FileUtils.mkdir_p(@installation.config_dir, mode: 0o700)
        @shell.run("chown", "#{@shell.me}:", @installation.config_dir, sudo: true) if @shell.root?
        @destinations.each do |destination|
          file = @installation.postgres_password_file(destination)
          if !File.exist?(file) || File.empty?(file)
            File.write(file, SecureRandom.hex(24), perm: 0o600) # no newline: CI's copy and the file must be the same string
            File.chmod(0o600, file)
            @shell.run("chown", "#{@shell.me}:", file, sudo: true) if @shell.root?
            @shell.tell "made #{file}"
          end
          put_secret("#{destination.upcase}_POSTGRES_PASSWORD", File.read(file), [ destination ])
          @shell.tell "#{destination.upcase}_POSTGRES_PASSWORD: from #{file}"
        end
        @shell.tell "Keep a copy of each in your password manager: GitHub never shows a secret back."
      end

      # Each destination that runs here says so in its file (DEPLOY_HOST), so
      # bin/kamal and bin/provision reach it from any machine; the list keeps
      # what ran here before, less what runs elsewhere now.
      def hosted_files!
        @destinations.each do |destination|
          settings = @installation.destination(destination)
          next if settings["DEPLOY_HOST"] == host

          @installation.write_destination(destination, settings.merge("DEPLOY_HOST" => host))
          @shell.tell "#{@installation.destination_file(destination)}: DEPLOY_HOST=#{host}"
        end
        @installation.hosted = ((@installation.hosted || []) | @destinations) - @elsewhere
      end

      # A machine's variable: on each of its destinations' environments, and at
      # the repository's level while this machine is the one that level names.
      def put_variable(name, value)
        @github.variable_set(name, value) if primary?
        @destinations.each { @github.variable_set(name, value, env: _1) } if @environments
      end

      def primary?
        return @primary if defined?(@primary)

        named = @github.variables["DEPLOY_HOST"].to_s
        @primary = named.empty? || named == host
      end

      def where_variables_go
        [ ("the repository's" if primary?), ("#{@destinations.join(", ")}'s environment#{"s" if @destinations.size > 1}" if @environments) ].compact.join(" and ")
      end

      def fork_approval!
        @shell.say "Pull requests from forks"
        if @github.fork_approval!
          @shell.tell "a run of anyone without write access waits for your approval"
        else
          @shell.warn "set it by hand: Settings → Actions → General → Approval for running fork pull request workflows → Require approval for all external contributors"
        end
      end

      # The household's runner belongs on a machine of its own.
      def runner!
        @shell.say "A runner on this machine"
        if Dir.exist?(File.join(@shell.my_home, "actions-runner"))
          @shell.warn "a runner here runs jobs on the machine that serves the app; move it (bin/provision-runner on its own machine, --remove-runner here)"
          @shell.warn "the runner here isn't ready (above)" unless @shell.run(File.join(@installation.root, "bin", "provision-runner"), allow_failure: true)
        else
          @shell.tell "none here: the jobs run on GitHub's runners, or on the household's own machine (RUNS_ON)"
        end
      end

      # A deploy secret where it belongs: each environment named, or the
      # repository while it has none; a copy the repository kept from before goes.
      def put_secret(name, value, destinations)
        if @environments
          destinations.each { @github.secret_set(name, value, env: _1) }
          @github.secret_delete(name)
        else
          @github.secret_set(name, value)
        end
      end

      def missing_in_an_environment?(name) = @environments && @destinations.any? { !@github.secret_names(env: _1).include?(name) }

      def notes = primary? ? first_machine_notes : another_machine_notes

      def short_name = host.split(".").first
      def tailnet_ip = @shell.capture("tailscale", "ip", "-4", allow_failure: true).to_s.lines.first.to_s.strip

      # The policy and the OAuth client exist from the first machine: this
      # one is added to them, and its destinations' hostnames move to a
      # tunnel of its own.
      def another_machine_notes
        @shell.say "Next, in the consoles (the deployment runbook, \"Moving a destination\")"
        @shell.tell <<~TXT
          1. Tailscale admin console → Access controls: add this machine beside the first,
             so the Deploy workflow's runners (tag:ci) reach its SSH too:

               "hosts":  "#{short_name}": "#{tailnet_ip}"
               "acls":   { "action": "accept", "src": ["tag:ci"], "dst": ["#{short_name}:22"] }
               "tests":  { "src": "tag:ci", "accept": ["#{short_name}:22"], "deny": ["#{short_name}:8080"] }

          2. Tailscale → Machines → #{short_name} → Disable key expiry (else CI loses it every 180 days).
          3. Cloudflare Zero Trust → Networks → Tunnels: a tunnel of this machine's own (cloudflared
             running here), and each destination's hostname moved to it from the old machine's:
        TXT
        @destinations.each { @shell.tell "     #{env["#{_1.upcase}_HOST"]} → http://127.0.0.1:8080#{", behind the Access application" if %w[staging dev].include?(_1)}" }
      end

      def first_machine_notes
        short = short_name
        ip = tailnet_ip
        secrets = if @environments
          <<~TXT.chomp
            read -rs ID; read -rs SECRET
            for environment in #{@destinations.join(" ")}; do
              gh secret set TS_OAUTH_CLIENT_ID --repo #{@github.repo} --env "$environment" --body "$ID"
              gh secret set TS_OAUTH_SECRET --repo #{@github.repo} --env "$environment" --body "$SECRET"
            done
            gh secret delete TS_OAUTH_CLIENT_ID --repo #{@github.repo}; gh secret delete TS_OAUTH_SECRET --repo #{@github.repo}  # copies from before, if any
          TXT
        else
          "     gh secret set TS_OAUTH_CLIENT_ID --repo #{@github.repo}\n     gh secret set TS_OAUTH_SECRET --repo #{@github.repo}"
        end
        @shell.say "Next, in the consoles (the deployment runbook, \"First time\")"
        @shell.tell <<~TXT
          1. Tailscale admin console → Access controls: let the Deploy workflow's runners
             (tag:ci) reach this machine's SSH and nothing else, keeping your devices as
             they are — in place of the default rule that lets everything reach everything:

               "tagOwners": { "tag:ci": ["autogroup:admin"] },
               "hosts": { "#{short}": "#{ip}" },
               "acls": [
                 { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*"] },
                 { "action": "accept", "src": ["tag:ci"], "dst": ["#{short}:22"] }
               ],
               "tests": [
                 { "src": "tag:ci", "accept": ["#{short}:22"], "deny": ["#{short}:8080"] }
               ]

          2. Tailscale → Machines → #{short} → Disable key expiry (else CI loses it every 180 days).
          3. Tailscale → Settings → OAuth clients → Generate: scope Keys → Auth keys (write), tag:ci. Then:
          #{secrets}
          4. Cloudflare Zero Trust → Networks → Tunnels → this tunnel → Public hostnames:
               #{env["STAGING_HOST"]} → http://127.0.0.1:8080, behind an Access application (Self-hosted, allow your email);
               #{env["DEV_HOST"]} → http://127.0.0.1:8080, behind the same Access application (a branch under test);
               #{env["PRODUCTION_HOST"]} → http://127.0.0.1:8080;
               #{env["DEMO_HOST"].to_s.empty? ? "the demo's host" : env["DEMO_HOST"]} → http://127.0.0.1:8080, nothing in front (the public demo) — added last,
                 after the demo is seeded: until the seed, the setup page would take the first visitor.
        TXT
      end
    end
  end
end
