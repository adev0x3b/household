# frozen_string_literal: true

module Provision
  # bin/provision: the first run sets up this machine for the pipeline and
  # the destinations it runs; every later run shows what runs here and
  # offers what comes next.
  class Wizard
    USAGE = <<~TXT
      bin/provision                     first run: .kamal/env, then the machine, then each destination you pick;
                                        later: what runs here, then a menu
      bin/provision status              what runs here, alone
      bin/provision machine             this machine again (Docker, the deploy user, the CI key, GitHub, the passwords)
      bin/provision installation        .kamal/env again (the hosts, a path to live under, the clock), then the repository's variables
      bin/provision <destination>       set up, or change the settings of, one destination
      bin/provision move <destination>  bring a destination here from the machine it runs on, its data with it where it has any
      bin/provision --rotate-ci-key     a new CI key (the old one stops working at once)
      bin/provision --remove-runner     a runner here, once no job runs on it (bin/provision-runner --remove)
      bin/provision --yes               every default, asking only what has none
    TXT
    FLAGS = %w[--yes --rotate-ci-key --remove-runner --help -h].freeze
    ACTIONS = {
      "set up a destination" => :add!, "change a destination's settings (it restarts through the Deploy workflow)" => :change!,
      "deploy a version to a destination" => :deploy!, "move a destination to this machine" => :move!, "the machine again" => :machine!,
      "the installation's names (.kamal/env: the hosts, a path to live under, the clock)" => :installation!, "rotate the CI key" => :rotate!,
      "quit" => nil
    }.freeze

    def initialize(argv, shell:, prompt:, installation:, root:, docker: nil, github: nil)
      @flags, @words = argv.partition { _1.start_with?("-") }
      @command = @words.first
      @shell = shell
      @prompt = prompt
      @installation = installation
      @root = root
      @docker = docker || Docker.new(shell)
      @github = github
    end

    def run
      unknown = @flags - FLAGS
      raise Stop, "unknown option: #{unknown.join(" ")}\n#{USAGE}" if unknown.any?
      return usage if @flags.intersect?(%w[--help -h])
      return remove_runner! if @flags.include?("--remove-runner")

      follow_moves! if set_up?
      case @command
      when nil then set_up? ? menu! : first_run!
      when "status" then status!
      when "machine" then machine!
      when "installation" then installation!
      when "move" then move!(@words[1])
      else destination!(@command)
      end
      0
    rescue Stop, Shell::Failed => e
      @shell.warn e.message
      1
    end

    private

    def set_up? = @installation.kamal_env?

    def usage
      @shell.tell USAGE
      0
    end

    def remove_runner! = @shell.run(File.join(@root, "bin", "provision-runner"), "--remove", allow_failure: true) ? 0 : 1

    # --- The first run ---------------------------------------------------------------

    def first_run!
      @shell.say "Household on this machine"
      kamal_env!
      destinations = ask_destinations
      @installation.hosted = destinations
      machine!(destinations)
      destinations.each do |name|
        next unless @prompt.yes?("Set up #{name} now? (the Tailscale step above must be done first when the jobs run on GitHub's runners)", default: true)

        pipeline(name).set_up!
      end
    end

    # .kamal/env, this installation's particulars, guessed from gh and Tailscale, or kept.
    def kamal_env!
      @shell.say ".kamal/env: this installation"
      current = @installation.kamal_env
      guessed = @shell.capture("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", as_me: true, allow_failure: true).to_s
      # A second machine of an installation starts from the repository's variables (this machine's name apart).
      if current.empty? && !guessed.empty?
        current = Pipeline::Github.new(@shell, repo: guessed).variables.slice(*Installation::KAMAL_ENV - %w[DEPLOY_HOST]).reject { |_, value| value.to_s.empty? }
        @shell.tell "the repository's variables say: #{current.keys.join(", ")}" if current.any?
      end
      repo = @prompt.ask("The repository (owner/name)", default: current["GITHUB_REPOSITORY"] || guessed, required: true)
      source = @prompt.ask("The code's repository, where the pipeline runs from a private one of its own (empty: this one)", default: current["SOURCE_REPOSITORY"].to_s)
      owner = @prompt.ask("Who owns the image on GHCR", default: current["KAMAL_REGISTRY_USERNAME"] || repo.split("/").first, required: true)
      host = @prompt.ask("This machine, as SSH reaches it (its tailnet name)", default: current["DEPLOY_HOST"] || tailnet_name, required: true)
      production = @prompt.ask("Production's address (the domain)", default: current["PRODUCTION_HOST"], required: true)
      staging = @prompt.ask("Staging's", default: current["STAGING_HOST"] || "staging.#{production}", required: true)
      dev = @prompt.ask("Dev's", default: current["DEV_HOST"] || "dev.#{production}", required: true)
      demo = if @prompt.yes?("A public demo?", default: !current["DEMO_HOST"].to_s.empty?)
        @prompt.ask("The demo's address", default: current["DEMO_HOST"] || "demo.#{production}", required: true)
      end
      mount = Mount.normalise(@prompt.ask("A path the app lives under (empty: the domain's root)", default: current["MOUNT_PATH"].to_s))
      zone = @prompt.ask("The household's clock, an IANA name (the clock before sign-in)", default: current["TIME_ZONE"] || machine_zone)
      @installation.write_kamal_env("DEPLOY_HOST" => host, "KAMAL_REGISTRY_USERNAME" => owner, "GITHUB_REPOSITORY" => repo, "SOURCE_REPOSITORY" => source, "PRODUCTION_HOST" => production,
                                    "STAGING_HOST" => staging, "DEV_HOST" => dev, "DEMO_HOST" => demo.to_s, "MOUNT_PATH" => mount, "TIME_ZONE" => zone)
      @shell.tell "written: #{@installation.kamal_env_file}"
    end

    def ask_destinations
      names = @prompt.ask("Which destinations run on this machine? (space-separated)", default: Settings::DESTINATIONS.join(" "), required: true).split
      unknown = names - Settings::DESTINATIONS
      raise Stop, "not a destination: #{unknown.join(" ")} (#{Settings::DESTINATIONS.join(", ")})" if unknown.any?

      names
    end

    # --- Later runs -------------------------------------------------------------------

    def menu!
      loop do
        status!
        action = ACTIONS.fetch(@prompt.choose("What next?", ACTIONS.keys, default: "quit"))
        break unless action

        send(action)
      end
    end

    def status!
      raise Stop, "nothing is set up here yet: run bin/provision" unless set_up?

      status = Status.new(installation: @installation, docker: @docker, shell: @shell)
      @shell.say "What runs here"
      @shell.tell status.table(status.rows(Settings::DESTINATIONS))
    end

    def machine!(destinations = @installation.hosted || ask_destinations)
      raise Stop, "no .kamal/env yet: run bin/provision, it asks for it" unless @installation.kamal_env?

      Pipeline::Machine.new(installation: @installation, shell: @shell, github: github, docker: @docker, destinations: destinations,
                            rotate_ci_key: @flags.include?("--rotate-ci-key")).run!
    end

    # .kamal/env asked again and the repository's variables set from it; each destination takes it on its next restart.
    def installation!
      kamal_env!
      Pipeline::Machine.new(installation: @installation, shell: @shell, github: github, docker: @docker, destinations: @installation.hosted || Settings::DESTINATIONS).variables!
      @shell.tell "Each destination takes it on its next restart (a change of path moves the installed app and its push subscriptions: the deployment runbook, \"Changing the mount\")."
    end

    def rotate!
      @flags << "--rotate-ci-key"
      machine!
    end

    def destination!(name)
      raise Stop, "nothing is set up here yet: run bin/provision" unless set_up?
      raise Stop, "#{name} is not a destination (#{Settings::DESTINATIONS.join(", ")})" unless Settings::DESTINATIONS.include?(name)

      destination = pipeline(name)
      destination.exists? ? destination.change! : destination.set_up!
    end

    def add!
      default = ((@installation.hosted || Settings::DESTINATIONS) - existing_names).first.to_s
      destination!(@prompt.ask("Which destination?", default: default, required: true))
    end

    # A machine new to the installation starts .kamal/env from the repository's variables.
    def move!(name = nil)
      kamal_env! unless set_up?
      name ||= @prompt.ask("Which destination?", default: "", required: true)
      raise Stop, "#{name} is not a destination (#{Settings::DESTINATIONS.join(", ")})" unless Settings::DESTINATIONS.include?(name)

      Pipeline::Move.new(name, installation: @installation, shell: @shell, prompt: @prompt, github: github, docker: @docker, root: @root).run!
    end

    # Each destination's file follows where its environment says it runs,
    # so the machine it moved away from reaches it there.
    def follow_moves!
      Settings::DESTINATIONS.each do |name|
        next unless @installation.destination?(name)

        host = github.deploy_host(name)
        settings = @installation.destination(name)
        next if host.nil? || settings["DEPLOY_HOST"] == host

        @installation.write_destination(name, settings.merge("DEPLOY_HOST" => host))
        @shell.tell "#{name} runs on #{host}: #{@installation.destination_file(name)} says so now"
      end
    end

    def change! = with_existing(&:change!)
    def deploy! = with_existing(&:deploy!)

    def with_existing
      names = existing_names
      raise Stop, "no destination is set up here yet" if names.empty?

      name = @prompt.choose("Which destination?", names, default: names.first)
      yield pipeline(name)
    end

    def existing_names = Settings::DESTINATIONS.select { @installation.destination?(_1) }

    def pipeline(name) = Pipeline::Destination.new(name, installation: @installation, shell: @shell, prompt: @prompt, github: github, docker: @docker, root: @root)

    def github
      @github ||= Pipeline::Github.new(@shell, repo: @installation.kamal_env.fetch("GITHUB_REPOSITORY") { raise Stop, "GITHUB_REPOSITORY isn't in .kamal/env" })
    end

    def tailnet_name
      JSON.parse(@shell.capture("tailscale", "status", "--json", allow_failure: true).to_s).dig("Self", "DNSName").to_s.chomp(".")
    rescue JSON::ParserError
      ""
    end

    def machine_zone = @shell.capture("timedatectl", "show", "-p", "Timezone", "--value", allow_failure: true).to_s.then { _1.empty? ? "UTC" : _1 }
  end
end
