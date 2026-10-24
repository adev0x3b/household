# frozen_string_literal: true

require "shellwords"

module Provision
  # What the pipeline runs, one row per destination: its file, its
  # containers (by Kamal's labels), the version they run, and whether the
  # app answers its health check.
  class Status
    Row = Data.define(:destination, :host, :configured, :version, :web, :job, :db, :health)

    def initialize(installation:, docker:, shell:)
      @installation = installation
      @docker = docker
      @shell = shell
    end

    def rows(destinations)
      containers = Hash.new { |cache, host| cache[host] = @docker.containers(host: host) }
      destinations.map { row(_1, containers[machine_of(_1)]) }
    end

    def table(rows)
      widths = { destination: 12, host: 24 }
      lines = [ format("  %-#{widths[:destination]}s %-#{widths[:host]}s %-9s %-38s %s", "destination", "host", "settings", "running", "health") ]
      rows.each do |row|
        running = [ row.web && "web #{row.version}".strip, row.job && "job", row.db && "db" ].compact
        running = running.empty? ? "–" : running.join(" · ") + (row.web&.start_with?("Up") ? "" : " (stopped)")
        lines << format("  %-#{widths[:destination]}s %-#{widths[:host]}s %-9s %-38s %s", row.destination, row.host.to_s[0, widths[:host]], row.configured ? "✓" : "–", running[0, 38], row.health || "–")
      end
      lines.join("\n")
    end

    private

    def row(destination, containers)
      web, job, db = %w[web job db].map { container_for(destination, _1, containers) }
      Row.new(destination: destination, host: host_for(destination), configured: @installation.destination?(destination),
              version: version_of(web), web: web&.fetch("Status"), job: job&.fetch("Status"), db: db&.fetch("Status"),
              health: web&.fetch("Status")&.start_with?("Up") ? health_of(destination) : nil)
    end

    def container_for(destination, role, containers)
      containers.find do |container|
        labels = container.fetch("labels")
        if role == "db"
          container.fetch("Names") == (destination == "production" ? "household-db" : "household-#{destination}-db")
        else
          labels["service"] == "household" && labels["destination"] == destination && labels["role"] == role
        end
      end
    end

    # Kamal names a container after the commit its image was built from.
    def version_of(web) = web && web.fetch("Names")[/-([0-9a-f]{7,40})\z/, 1].to_s[0, 7]

    def host_for(destination) = [ app_host(destination), machine_of(destination) ].compact.join(" @ ")
    def app_host(destination) = @installation.kamal_env["#{destination.upcase}_HOST"]

    # Another machine, where the destination's file names one; nil for this one.
    def machine_of(destination) = @installation.remote?(destination) ? @installation.host_of(destination) : nil

    # The app's health check, asked through kamal-proxy the way a visitor reaches it.
    def health_of(destination)
      mount = @installation.kamal_env["MOUNT_PATH"].to_s.chomp("/")
      curl = [ "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", "-H", "Host: #{app_host(destination)}", "http://127.0.0.1:8080#{mount}/up" ]
      machine = machine_of(destination)
      curl = [ "ssh", "-o", "BatchMode=yes", "deploy@#{machine}", Shellwords.join(curl) ] if machine
      @shell.capture(*curl, allow_failure: true)
    end
  end
end
