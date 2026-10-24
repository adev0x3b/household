# frozen_string_literal: true

require "shellwords"
require "yaml"

module Provision
  module Pipeline
    # One destination brought to this machine from the one it runs on
    # (bin/provision move): this machine set up for it, its data carried over
    # where it holds any worth keeping, a version deployed here through the
    # Deploy workflow, then the old copy removed there, its volumes kept.
    class Move
      # Staging rehearses a release on a copy of production's database,
      # made on their machine, so the two belong together.
      TOGETHER = %w[staging production].freeze
      # What copies a volume's files, on each side.
      TAR_IMAGE = "alpine:3.22"
      # Where kamal-proxy listens on every machine, and the Cloudflare tunnel points.
      PROXY_PORT = 8080

      attr_reader :name

      def initialize(name, installation:, shell:, prompt:, github:, docker:, root:)
        @name = name
        @installation = installation
        @shell = shell
        @prompt = prompt
        @github = github
        @docker = docker
        @root = root
        @destination = Destination.new(name, installation:, shell:, prompt:, github:, docker:, root:)
      end

      def run!
        @shell.say "#{name}, moved to this machine (#{here})"
        from = @github.deploy_host(name)
        raise Stop, already_here if from == here

        ready_for_the_proxy!
        apart_from_its_partner!
        reach!(from) if from
        version = from && running_version(from)
        carry = from && carry?(from)
        fresh_volumes! unless carry

        set_up_machine!
        @destination.configure!(arriving: true)

        begin
          stop_old!(from) if carry
          if carry
            volumes.each { copy_volume!(_1, from) }
            take_this_machines_password!
          end
          @destination.boot!(version)
        rescue Stop, Shell::Failed
          start_old!(from) if carry
          raise
        end
        @destination.after_boot! unless carry
        remove_old!(from) if from
        notes(from)
      end

      private

      def here = @installation.this_host

      # Its environment names this machine from the setup on, so a move that
      # stopped after it is finished by deploying here.
      def already_here
        "#{name} runs on this machine already, as its environment says. If a move here stopped before #{name} came up, " \
          "deploy it again: bin/provision, then \"deploy a version to a destination\""
      end

      # The first deploy here creates kamal-proxy on the port. With the port
      # held by something else, or a proxy left stopped by an earlier try, the
      # proxy runs without the network the app is on, and the new copy never
      # answers its health check.
      def ready_for_the_proxy!
        proxy = @docker.containers.find { _1["Names"] == "kamal-proxy" }
        return if proxy && proxy["State"] == "running"
        raise Stop, "a stopped kamal-proxy is left here from an earlier try, and would start without its network: docker rm kamal-proxy, then run this again" if proxy
        return if @shell.capture("ss", "-Hltn", "sport = :#{PROXY_PORT}", allow_failure: true).to_s.strip.empty?

        raise Stop, "something here holds port #{PROXY_PORT}, where #{name}'s proxy listens (sudo ss -ltnp 'sport = :#{PROXY_PORT}' names it): free it, then run this again"
      end

      def apart_from_its_partner!
        return unless TOGETHER.include?(name)

        partner = (TOGETHER - [ name ]).first
        return if @github.deploy_host(partner) == here

        @shell.warn "#{partner} doesn't run here: until it does, a release can't be rehearsed on staging (bin/provision move #{partner} next)"
        raise Stop, "Left as it is." unless @prompt.yes?("Move #{name} without #{partner}?", default: false)
      end

      # Kamal and the copies below log in to the old machine as deploy, and
      # trust its host key as the Deploy workflow recorded it, read before
      # this machine's takes its place.
      def reach!(from)
        known = @github.known_host(name)
        KnownHosts.new(@shell).trust!(known) if known&.start_with?("#{from} ")
        return if @shell.ok?("ssh", "-o", "BatchMode=yes", "deploy@#{from}", "true", as_me: true)

        key = Dir[File.join(@shell.my_home, ".ssh", "id_*.pub")].first
        raise Stop, "no ~/.ssh/id_*.pub to log in to #{from} with: ssh-keygen -t ed25519, then run this again" unless key

        raise Stop, <<~TXT.chomp
          this machine can't log in to #{from} as deploy. On #{from}, let your key in, then run this again:
            echo '#{%(from="#{Machine::TAILNET}" #{File.read(key).strip})}' | sudo tee -a ~deploy/.ssh/authorized_keys
        TXT
      end

      # The version the old copy serves, so the move changes the machine and
      # nothing else; nil where nothing runs there, and one is asked.
      def running_version(from)
        web = @docker.containers(host: from).find do |container|
          labels = container.fetch("labels")
          labels["service"] == "household" && labels["destination"] == name && labels["role"] == "web" && container["State"] == "running"
        end
        web && web.fetch("Names")[/-(\h{40})\z/, 1]
      end

      # Staging's and production's data comes along by default; dev's and the
      # demo's start again, as they do on every fresh preview and every night.
      def carry?(from)
        carry = @prompt.yes?("Bring #{name}'s data from #{from}? (#{name} stops there while it is copied)", default: TOGETHER.include?(name))
        raise Stop, "Left as it is." if carry && name == "production" && !@prompt.yes?("Production is down until the copy is done and the deploy healthy. Go on?", default: true)

        carry
      end

      # Volumes left here from an earlier time would come back under the new
      # copy, with a database whose password is another's.
      def fresh_volumes!
        left = @shell.capture("docker", "volume", "ls", "-q", allow_failure: true).to_s.split & volumes
        return if left.empty?

        raise Stop, "this machine still has #{name}'s volumes from before: docker volume rm #{left.join(" ")}, to start it fresh"
      end

      # This machine's steps for every destination it runs, this one
      # included, with a new CI key for them all: the environments that
      # already hold one hold another machine's.
      def set_up_machine!
        Machine.new(installation: @installation, shell: @shell, github: @github, docker: @docker,
                    destinations: (@installation.hosted || []) | [ name ], rotate_ci_key: true, claiming: [ name ]).run!
      end

      def stop_old!(from)
        @shell.say "#{name} stops on #{from}"
        kamal(from, "app", "stop")
        kamal(from, "accessory", "stop", "db")
      end

      def start_old!(from)
        @shell.warn "#{name} starts again on #{from}; its environment names this machine now, so deploys come here until bin/provision move #{name} runs there"
        kamal(from, "accessory", "start", "db", allow_failure: true)
        kamal(from, "app", "start", allow_failure: true)
      end

      # Streamed over SSH from a container on the old machine into one here,
      # owners and modes kept, while neither database runs.
      def copy_volume!(volume, from)
        @shell.say "#{volume}, from #{from}"
        out = Shellwords.join([ "docker", "run", "--rm", "-v", "#{volume}:/from:ro", TAR_IMAGE, "tar", "-C", "/from", "-cf", "-", "." ])
        into = Shellwords.join([ "docker", "run", "--rm", "-i", "-v", "#{volume}:/to", TAR_IMAGE, "tar", "-C", "/to", "-xpf", "-" ])
        @shell.run("bash", "-o", "pipefail", "-c", "ssh -o BatchMode=yes deploy@#{Shellwords.escape(from)} #{Shellwords.escape(out)} | #{into}", as_me: true)
      end

      # The copied database keeps the role's password from its first boot on
      # the old machine; it takes this machine's own instead, set in
      # Postgres's single-user mode before anything connects, so the old
      # machine's never has to leave it.
      def take_this_machines_password!
        password = File.read(@installation.postgres_password_file(name))
        sql = "ALTER ROLE household PASSWORD '#{password.gsub("'", "''")}';\n"
        @shell.run("docker", "run", "--rm", "-i", "-v", "#{database_volume}:/var/lib/postgresql/data", database_image,
                   "postgres", "--single", "-D", "/var/lib/postgresql/data", "household_production", stdin: sql, as_me: true)
      end

      # The containers and the route go; the volumes stay, until removed by
      # hand. The new copy serves already, so what fails here is only told.
      def remove_old!(from)
        @shell.say "#{name}, removed from #{from}"
        removed = kamal(from, "app", "remove", allow_failure: true) & kamal(from, "accessory", "remove", "db", "-y", allow_failure: true)
        @shell.warn "some of #{name} is left on #{from}: bin/kamal app remove -d #{name} and bin/kamal accessory remove db -d #{name}, with DEPLOY_HOST=#{from}" unless removed
        @shell.tell "#{name}'s volumes stay on #{from}. Once it serves well from here: ssh deploy@#{from} docker volume rm #{volumes.join(" ")}"
      end

      def notes(from)
        @shell.say "Then, in Cloudflare Zero Trust → Networks → Tunnels"
        @shell.tell "  #{@destination.app_host} → http://127.0.0.1:8080 on this machine's tunnel#{", taken off #{from}'s" if from}"
      end

      # bin/kamal on the old machine: the same configuration, its DEPLOY_HOST
      # in the environment, which bin/kamal's files never overwrite.
      def kamal(from, *argv, allow_failure: false)
        @shell.run("env", "DEPLOY_HOST=#{from}", File.join(@root, "bin", "kamal"), *argv, "-d", name, as_me: true, allow_failure: allow_failure)
      end

      # The configuration as Kamal reads it, from its YAML on: a warning the bundle prints comes before it.
      def config
        @config ||= YAML.unsafe_load(@shell.capture(File.join(@root, "bin", "kamal"), "config", "-d", name, as_me: true)[/^---.*/m].to_s)
      end

      def database = config.fetch(:accessories).fetch("db")
      def database_image = database.fetch("image")
      def database_volume = database.fetch("volumes").first.split(":").first

      # The app's (Kamal gives them as --volume arguments) and the database's.
      def volumes
        @volumes ||= (config.fetch(:volume_args, []).each_slice(2).map(&:last) + database.fetch("volumes", [])).map { _1.split(":").first }
      end
    end
  end
end
