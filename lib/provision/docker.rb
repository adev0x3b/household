# frozen_string_literal: true

require "shellwords"

module Provision
  # Docker on this machine — installed from Docker's own apt repository,
  # started at boot, usable by the person at the keyboard — and what runs on
  # it: every container with Kamal's labels (service, destination and role),
  # on this machine or on another one Kamal reaches as `deploy`.
  class Docker
    def initialize(shell)
      @shell = shell
    end

    def install!
      @shell.say "Docker Engine"
      if @shell.ok?("docker", "--version")
        @shell.tell "already installed: #{@shell.capture("docker", "--version")}"
      else
        codename = @shell.capture("sh", "-c", ". /etc/os-release && echo \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\"")
        arch = @shell.capture("dpkg", "--print-architecture")
        @shell.run("apt-get", "update", "-qq", sudo: true)
        @shell.run("apt-get", "install", "-y", "ca-certificates", "curl", sudo: true)
        @shell.run("install", "-m", "0755", "-d", "/etc/apt/keyrings", sudo: true)
        @shell.run("curl", "-fsSL", "https://download.docker.com/linux/ubuntu/gpg", "-o", "/etc/apt/keyrings/docker.asc", sudo: true)
        @shell.run("chmod", "a+r", "/etc/apt/keyrings/docker.asc", sudo: true)
        @shell.run("tee", "/etc/apt/sources.list.d/docker.list", sudo: true,
                                                                 stdin: "deb [arch=#{arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu #{codename} stable\n")
        @shell.run("apt-get", "update", "-qq", sudo: true)
        @shell.run("apt-get", "install", "-y", "docker-ce", "docker-ce-cli", "containerd.io", "docker-buildx-plugin", "docker-compose-plugin", sudo: true)
      end
      # Up at boot: the containers' restart policy brings the app back with it.
      @shell.run("systemctl", "enable", "--now", "docker", sudo: true)
      unless @shell.capture("id", "-nG", @shell.me).split.include?("docker")
        @shell.run("usermod", "-aG", "docker", @shell.me, sudo: true)
        @shell.tell "added #{@shell.me} to the docker group — it applies to new logins: log out and in, or 'exec sudo su -l #{@shell.me}'"
      end
    end

    # The labels Kamal gives a container to say what it is.
    LABELS = %w[service destination role].freeze
    FORMAT = ([ "{{.Names}}", "{{.Image}}", "{{.Status}}", "{{.State}}" ] + LABELS.map { %({{.Label "#{_1}"}}) }).join("\t")

    # Every container, running or not, as `docker ps` tells it, with the
    # labels above (a hash; the ones it lacks left out).
    def containers(host: nil)
      output = @shell.capture(*on(host, "docker", "ps", "-a", "--no-trunc", "--format", FORMAT), allow_failure: true).to_s
      output.each_line.filter_map do |line|
        names, image, status, state, *labels = line.chomp.split("\t", -1)
        next if names.to_s.empty?

        { "Names" => names, "Image" => image, "Status" => status, "State" => state,
          "labels" => LABELS.zip(labels).to_h.reject { |_, value| value.to_s.empty? } }
      end
    end

    # A command inside a running container; stdin given to it, never on the command line.
    def exec(container, *argv, env: {}, stdin: nil, host: nil)
      flags = (stdin ? [ "-i" ] : []) + env.flat_map { |name, value| [ "-e", "#{name}=#{value}" ] }
      @shell.run(*on(host, "docker", "exec", *flags, container, *argv), stdin: stdin)
    end

    private

    # Here, or over SSH as deploy on the machine a destination runs on.
    def on(host, *argv) = host ? [ "ssh", "-o", "BatchMode=yes", "deploy@#{host}", Shellwords.join(argv) ] : argv
  end
end
