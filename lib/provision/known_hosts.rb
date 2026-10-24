# frozen_string_literal: true

require "shellwords"

module Provision
  # A machine's host key, trusted from what bin/provision recorded rather
  # than from whatever answers: added to your ~/.ssh/known_hosts and looked
  # up by the machine's name alone (HostKeyAlias, which Kamal's net-ssh reads
  # from ~/.ssh/config too).
  class KnownHosts
    def initialize(shell)
      @shell = shell
    end

    # line: "<host> <type> <key>", as DEPLOY_KNOWN_HOSTS holds it.
    def trust!(line)
      host = line.split.first
      ssh_dir = File.join(@shell.my_home, ".ssh")
      known_hosts = File.join(ssh_dir, "known_hosts")
      unless @shell.ok?("ssh-keygen", "-F", host, "-f", known_hosts, as_me: true)
        @shell.run("install", "-d", "-m", "700", ssh_dir, as_me: true)
        append(known_hosts, "#{line}\n")
        @shell.tell "added #{host} to your ~/.ssh/known_hosts"
      end
      config = File.join(ssh_dir, "config")
      return if File.exist?(config) && File.read(config).include?("HostKeyAlias #{host}")

      append(config, "Host #{host}\n  HostKeyAlias #{host}\n")
      @shell.tell "added HostKeyAlias for #{host} to your ~/.ssh/config"
    end

    private

    def append(path, text) = @shell.run("sh", "-c", "cat >> #{Shellwords.escape(path)}", as_me: true, stdin: text)
  end
end
