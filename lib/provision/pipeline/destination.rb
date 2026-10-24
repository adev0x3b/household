# frozen_string_literal: true

module Provision
  module Pipeline
    # One destination of the pipeline: its settings asked and written to its
    # file, mirrored to its GitHub environment, then the Deploy workflow
    # dispatched and followed — everything that changes what runs goes
    # through it — and the first account made in the running container.
    class Destination
      attr_reader :name

      def initialize(name, installation:, shell:, prompt:, github:, docker:, root:)
        @name = name
        @installation = installation
        @shell = shell
        @prompt = prompt
        @github = github
        @docker = docker
        @root = root
      end

      def current = @installation.destination(name)
      def exists? = @installation.destination?(name)
      def app_host = @installation.kamal_env["#{name.upcase}_HOST"].to_s

      def set_up!
        configure!
        boot!
        after_boot!
        cloudflare_note
      end

      def change!
        configure!
        return @shell.tell("#{name} takes them on its next boot.") unless web_container

        @shell.say "#{name} restarts with them"
        dispatch(action: "restart")
      end

      def deploy!(version = nil)
        version ||= @prompt.ask("The commit to deploy (one on main whose image CI built)", default: @github.newest_main_version.to_s, required: true)
        raise Stop, "#{version} is not on main: only main's commits reach #{name}" unless on_main?(version)

        confirm! if name == "production"
        dispatch(action: "deploy", version: version)
      end

      # Its settings asked, written to its file and mirrored. Arriving from
      # another machine, the file here starts from the environment's values,
      # and a key left blank stays as GitHub has it: only that machine's file
      # knew it.
      def configure!(arriving: false)
        pairs = arriving ? ask(from_environment, kept: @github.secret_names(env: name)) : ask
        write(pairs)
        mirror!(pairs, keep_blank_keys: arriving)
      end

      # The first boot: dev a preview of main on fresh data (seeded, with its
      # admin), the others a deploy of the version given, else of one asked.
      def boot!(version = nil)
        if name == "dev"
          dispatch(action: "preview", branch: "main", fresh: true)
        else
          deploy!(version)
        end
      end

      # The demo household where accounts are open, dev's from its fresh
      # preview, else the admin — or the setup page, behind its one-time code.
      def after_boot!
        return if name == "dev"

        if current["OPEN_ACCOUNTS"].to_s.empty? || (current["OPEN_ACCOUNTS"] == Settings.find("OPEN_ACCOUNTS").default_for(name) && name != "demo")
          if @prompt.yes?("Make the admin now? (else the setup page makes it, after the code printed next)", default: true)
            username = @prompt.ask("Username", default: "admin", required: true)
            email = @prompt.ask("Email", default: "", required: true)
            admin!(username: username, email: email, password: @prompt.secret("Password (12 characters at least)", required: true))
          else
            setup_code!
          end
        else
          seed!
        end
      end

      # Mirrored: the environment's variables and secrets among the catalogue's
      # names made equal to the file — set where the file has a value, deleted
      # where it has none (the destination's default then applies).
      def mirror!(pairs, keep_blank_keys: false)
        unless @github.environment?(name)
          @shell.warn "GitHub has no environment #{name}: the settings stay in #{@installation.destination_file(name)} for deploys by hand, and the Deploy workflow's carry none (GitHub Free: environments on public repositories; run `bin/provision machine` once it is public)"
          return
        end

        @shell.say "#{name}'s settings, mirrored to its GitHub environment"
        variables = @github.variables(env: name)
        secrets = @github.secret_names(env: name)
        Settings.for(name).each do |setting|
          value = pairs[setting.name].to_s
          if setting.secret?
            if value.empty?
              @github.secret_delete(setting.name, env: name) if secrets.include?(setting.name) && !keep_blank_keys
            else
              @github.secret_set(setting.name, value, env: name)
            end
          elsif value.empty?
            @github.variable_delete(setting.name, env: name) if variables.key?(setting.name)
          elsif variables[setting.name] != value
            @github.variable_set(setting.name, value, env: name)
          end
        end
      end

      def seed!
        @shell.say "The demo household"
        @docker.exec(web_container!, "bin/rails", "demo:seed", host: machine)
      end

      def admin!(username:, email:, password:)
        @docker.exec(web_container!, "bash", "-c", "read -r PASSWORD; export PASSWORD; bin/rails admin:create", env: { "USERNAME" => username, "EMAIL" => email }, stdin: "#{password}\n", host: machine)
      end

      # Another machine, where the destination's file names one; nil for this one.
      def machine = @installation.remote?(name) ? @installation.host_of(name) : nil

      # The running web container, found by Kamal's labels, here or there.
      def web_container
        @docker.containers(host: machine).find do |container|
          labels = container.fetch("labels")
          labels["service"] == "household" && labels["destination"] == name && labels["role"] == "web" && container["State"] == "running"
        end&.fetch("Names")
      end

      private

      def ask(known = {}, kept: [])
        @shell.say "#{name}: its settings"
        @shell.tell "Its keys on GitHub stay as they are unless you type new ones." if known.any?
        Questionnaire.new(@prompt).settings(Settings.for(name), Settings.defaults(name).merge(known).merge(current), kept: kept)
      end

      # What the environment holds: its variables' values, and every key blank, since GitHub never shows one back.
      def from_environment
        variables = @github.variables(env: name)
        Settings.for(name).to_h { [ _1.name, _1.secret? ? "" : variables.fetch(_1.name, _1.default_for(name)) ] }
      end

      # The file keeps where the destination runs: its machine's name, or this one's.
      def write(pairs)
        machine = current["DEPLOY_HOST"].to_s.then { _1.empty? ? @installation.this_host : _1 }
        @installation.write_destination(name, (machine.empty? ? {} : { "DEPLOY_HOST" => machine }).merge(pairs))
      end

      def dispatch(**fields)
        raise Stop, "no runner takes jobs now: RUNS_ON names #{@github.runs_on.inspect} and none of those is online" unless @github.runner_available?

        before = @github.latest_run_id
        @github.dispatch(destination: name, reason: "bin/provision: #{fields[:action]} #{name}", **fields)
        id = wait_for_run(before)
        @shell.tell "the Deploy workflow runs: https://github.com/#{@github.repo}/actions/runs/#{id}"
        @github.watch(id) or raise Stop, "the run failed; its log says why"
      end

      def wait_for_run(before, every: 3, timeout: 90)
        waited = 0
        loop do
          id = @github.latest_run_id
          return id if id && id != before
          raise Stop, "the Deploy workflow didn't start within #{timeout} s: gh run list --workflow deploy.yml" if waited >= timeout

          sleep every
          waited += every
        end
      end

      def on_main?(version)
        @shell.run("git", "-C", @root, "fetch", "-q", "origin", "main", allow_failure: true)
        @shell.ok?("git", "-C", @root, "merge-base", "--is-ancestor", version, "origin/main")
      end

      def confirm!
        typed = @prompt.ask("This changes production. Type its name to go on", default: "")
        raise Stop, "Left as it is." unless typed == "production"
      end

      def web_container! = web_container or raise Stop, "no running web container for #{name} on #{machine || 'this machine'}"

      # The code the setup page asks for, printed by the app itself, so the
      # address can be reached before the first account without a stranger
      # making it first.
      def setup_code!
        @shell.say "#{name}: the setup page's code"
        @docker.exec(web_container!, "bin/rails", "setup:code", host: machine)
        @shell.tell "Open https://#{app_host}#{@installation.kamal_env["MOUNT_PATH"].to_s.chomp("/")}/setup and type it there."
      end

      def cloudflare_note
        gate = %w[staging dev].include?(name) ? "behind an Access application" : (name == "demo" ? "nothing in front, now that it is seeded" : "nothing in front")
        @shell.say "Then, in Cloudflare Zero Trust → the tunnel → Public hostnames"
        @shell.tell "  #{app_host} → http://127.0.0.1:8080, #{gate}"
      end
    end
  end
end
