# frozen_string_literal: true

module Provision
  # What this machine holds for the pipeline: the destinations it runs, in
  # ~/.config/household/installation.env, each destination's file beside it,
  # and .kamal/env in the checkout (the deployment runbook, "First time").
  class Installation
    KAMAL_ENV = %w[DEPLOY_HOST KAMAL_REGISTRY_USERNAME GITHUB_REPOSITORY SOURCE_REPOSITORY PRODUCTION_HOST STAGING_HOST DEV_HOST DEMO_HOST MOUNT_PATH TIME_ZONE].freeze

    attr_reader :config_dir, :root

    def initialize(config_dir:, root:)
      @config_dir = config_dir
      @root = root
    end

    HEADER = "Which destinations run on this machine. bin/provision asked once."

    # The destinations that run on this machine, said on the first run; nil until then.
    def hosted
      names = installation_env["DESTINATIONS"].to_s.split(",").map(&:strip).reject(&:empty?)
      names.empty? ? nil : names
    end

    def hosted=(names)
      write_installation_env(installation_env.merge("DESTINATIONS" => names.join(",")))
    end

    # This machine, as .kamal/env names it; where a destination runs (its
    # file's DEPLOY_HOST, else here); whether that is another machine.
    def this_host = kamal_env["DEPLOY_HOST"].to_s
    def host_of(name) = destination(name)["DEPLOY_HOST"].to_s.then { _1.empty? ? this_host : _1 }
    def remote?(name) = !this_host.empty? && host_of(name) != this_host

    def destination_file(name) = File.join(config_dir, "#{name}.env")
    def destination?(name) = File.exist?(destination_file(name))
    def destination(name) = EnvFile.read(destination_file(name))

    def write_destination(name, pairs)
      EnvFile.write(destination_file(name), pairs,
                    header: "#{name}'s settings, read by bin/kamal -d #{name} before .kamal/env and mirrored to its GitHub environment. Written by bin/provision, and changed by bin/provision #{name}. Readable by you alone: it holds the keys.")
    end

    def kamal_env_file = File.join(root, ".kamal", "env")
    def kamal_env = EnvFile.read(kamal_env_file)
    def kamal_env?(name = nil) = name ? !kamal_env[name].to_s.empty? : File.exist?(kamal_env_file)

    def write_kamal_env(pairs)
      EnvFile.write(kamal_env_file, pairs.slice(*KAMAL_ENV).reject { |_, value| value.to_s.empty? },
                    header: File.read(File.join(root, ".kamal", "env.example")).lines.take_while { _1.start_with?("#") }.join.gsub(/^# ?/, ""))
      File.chmod(0o644, kamal_env_file)
    end

    def postgres_password_file(name) = File.join(config_dir, "#{name}-postgres-password")

    private

    def installation_env = EnvFile.read(File.join(config_dir, "installation.env"))
    def write_installation_env(pairs) = EnvFile.write(File.join(config_dir, "installation.env"), pairs, header: HEADER)
  end
end
