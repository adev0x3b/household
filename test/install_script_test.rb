# frozen_string_literal: true

require "test_helper"
require "open3"
require "pty"

# install.sh end to end with --yes, on a machine whose docker, tailscale,
# sudo, curl, crontab and ss are stand-ins that record what they were asked:
# each way of reaching the app writes its few lines, a port another program
# holds is asked again, a first start that fails can be tried again, the
# release is checked
# before anything is installed, the setup code is the app's, and the
# household command backs up, updates, puts the old version back and
# uninstalls what it is told to. What is typed back is typed on a terminal
# of the test's own.
class InstallScriptTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("install.sh").to_s
  CODE = "K7QM-2XRD-9VWP-HC4T"
  IMAGE = "ghcr.io/owner/household:2026.11.1@sha256:#{"a" * 64}"

  setup do
    @root = Dir.mktmpdir
    @home = File.join(@root, "home")
    @bin = File.join(@root, "bin")
    @release = File.join(@root, "release")
    FileUtils.mkdir_p([ @home, @bin, @release ])
    File.write(File.join(@release, "compose.yml"), Rails.root.join("compose.yml").read.gsub("${HOUSEHOLD_IMAGE}", IMAGE))
    File.write(File.join(@release, "release.json"), %({\n  "version": "2026.11.1",\n  "tag": "v2026.11.1",\n  "image": "#{IMAGE}"\n}\n))
    FileUtils.cp(SCRIPT, File.join(@release, "install.sh"))
    fake "docker", <<~SH
      case "$*" in
        "version --format"*) echo 27.3.1 ;;
        "compose version --short") echo 2.29.7 ;;
        *"exec -T -e RAILS_LOG_LEVEL=warn web bin/rails setup:code")
          [ -f "#{@root}/account" ] && { echo "Someone has an account already." >&2; exit 3; }
          echo "Setup code: #{CODE}" >&2
          echo "#{CODE}" ;;
        *"exec -T db pg_dump"*) echo "the database" ;;
        *"config --images") printf '%s\n' "#{IMAGE}" postgres:16 ;;
        *"--entrypoint tar web czf"*) echo "the files" ;;
        *"up -d --wait --wait-timeout"*)
          # A release that never comes up healthy, once.
          if [ -f "#{@root}/unhealthy" ]; then rm "#{@root}/unhealthy"; exit 1; fi ;;
      esac
    SH
    fake "tailscale", <<~SH
      case "$1" in status) echo '{ "Self": { "DNSName": "box.tail1234.ts.net.", "OS": "linux" } }' ;; esac
    SH
    # sudo -v only asks for the password, so the stand-in runs nothing for it.
    fake "sudo", %([ "$1" = -v ] || "$@")
    # The release on GitHub: whatever file the URL names, from @release.
    fake "curl", <<~SH
      while [ $# -gt 1 ]; do [ "$1" = -o ] && out=$2; shift; done
      cp "#{@release}/${1##*/}" "$out"
    SH
    fake "timedatectl", "echo Europe/Rome"
    # The ports another program listens on are the lines of busy.
    fake "ss", <<~SH
      port=${*##*:}
      if grep -qx "$port" "#{@root}/busy" 2> /dev/null; then echo "LISTEN 0 4096 127.0.0.1:$port 0.0.0.0:*"; fi
    SH
    # Reads its whole input before writing, as the real one does: the lines
    # it is given come from its own listing.
    fake "crontab", <<~SH
      if [ "$1" = -l ]; then cat "#{@root}/crontab" 2> /dev/null; else cat > "#{@root}/crontab.new" && mv "#{@root}/crontab.new" "#{@root}/crontab"; fi
    SH
  end

  teardown { FileUtils.rm_rf(@root) }

  test "only this computer: plain HTTP on localhost, the env file readable by its owner alone, the command beside it, the code printed" do
    out = install!(exposure: "local")
    env = env_file
    assert_equal %w[local localhost 127.0.0.1 8080 off Europe/Rome], env.values_at("EXPOSURE", "APP_HOST", "BIND", "PORT", "FORCE_SSL", "TIME_ZONE")
    assert_match(/\A\h{48}\z/, env.fetch("POSTGRES_PASSWORD"))
    assert_equal "100600", File.stat(File.join(dir, "household.env")).mode.to_s(8)
    assert_equal IMAGE, YAML.safe_load_file(File.join(dir, "compose.yml"), aliases: true).dig("services", "web", "image")
    assert File.executable?(File.join(dir, "household"))
    assert_equal File.read(SCRIPT), File.read(File.join(dir, "household"))

    assert_includes out, "Household 2026.11.1"
    assert_includes out, "Docker 27.3.1 ✓  Compose 2.29.7 ✓"
    assert_match(%r{Open   http://localhost:8080$}, out)
    assert_match(/Code   #{CODE}$/, out)
    files = "-f #{dir}/compose.yml --env-file #{dir}/household.env"
    assert_equal [ "compose --progress quiet #{files} pull", "compose --progress quiet #{files} up -d --wait --wait-timeout 300", "compose #{files} exec -T -e RAILS_LOG_LEVEL=warn web bin/rails setup:code" ],
                 calls("docker").grep(/ -f /)
  end

  test "each way of reaching it sets its own few lines" do
    {
      "network" => [ { "HOUSEHOLD_HOST" => "192.168.1.20" }, %w[0.0.0.0 192.168.1.20 8080 off], "http://192.168.1.20:8080" ],
      "tailscale" => [ {}, %w[127.0.0.1 box.tail1234.ts.net 8080 on], "https://box.tail1234.ts.net" ],
      "public" => [ { "HOUSEHOLD_HOST" => "home.example.com" }, %w[0.0.0.0 home.example.com 80 on], "https://home.example.com" ],
      "proxy" => [ { "HOUSEHOLD_HOST" => "home.example.com", "HOUSEHOLD_PORT" => "9090" }, %w[127.0.0.1 home.example.com 9090 on], "https://home.example.com" ]
    }.each do |exposure, (answers, expected, address)|
      FileUtils.rm_rf(dir)
      out = install!(exposure: exposure, env: answers)
      assert_equal expected, env_file.values_at("BIND", "APP_HOST", "PORT", "FORCE_SSL"), exposure
      assert_includes out, "Open   #{address}", exposure
    end
    assert_includes calls("tailscale"), "serve --bg --https=443 http://127.0.0.1:8080"
  end

  test "a certificate of its own answers on 80 and 443 for its name" do
    install!(exposure: "public", env: { "HOUSEHOLD_HOST" => "home.example.com" })
    assert_equal %w[home.example.com 80 443], env_file.values_at("TLS_DOMAIN", "PORT", "TLS_PORT")
  end

  test "a Cloudflare Tunnel: the token and the profile that starts cloudflared, nothing published beyond the machine" do
    out = install!(exposure: "cloudflare", env: { "TUNNEL_TOKEN" => "eyJ-token", "HOUSEHOLD_HOST" => "home.example.com" })
    assert_equal %w[eyJ-token cloudflare 127.0.0.1 on], env_file.values_at("TUNNEL_TOKEN", "COMPOSE_PROFILES", "BIND", "FORCE_SSL")
    assert_includes out, "points at http://web:80"
  end

  test "a way of reaching it that lacks its name stops before anything is written" do
    out = install!(exposure: "public", success: false)
    assert_includes out, "needs the name people will use"
    assert_not File.exist?(File.join(dir, "household.env"))
    assert_empty calls("docker").grep(/ -f /)
  end

  test "a port another program holds: the next free one taken, and kept when asked again how people reach it" do
    busy 8080, 8081, 8443
    out = install!(exposure: "local")
    assert_includes out, "Port 8080 is taken by another program on this machine."
    assert_equal %w[8082 8444], env_file.values_at("PORT", "TLS_PORT")
    assert_match(%r{Open   http://localhost:8082$}, out)

    out = household("config", "--yes", env: { "HOUSEHOLD_EXPOSURE" => "network", "HOUSEHOLD_HOST" => "192.168.1.20" })
    assert_not_includes out, "is taken"
    assert_includes out, "Household is at http://192.168.1.20:8082"
  end

  test "a port another program holds, asked at a terminal" do
    busy 8080
    out = at_a_terminal(SCRIPT, "--from", @release, answers: [ "", "1", "9090", "n" ])
    assert_includes out, "Port 8080 is taken by another program on this machine."
    assert_includes out, "Which port should Household use? [8081]"
    assert_equal "9090", env_file.fetch("PORT")
    assert_match(%r{Open   \S*http://localhost:9090}, out)
  end

  test "a certificate of its own needs 80 and 443, and stops before anything is written when another program holds one" do
    busy 443
    out = install!(exposure: "public", env: { "HOUSEHOLD_HOST" => "home.example.com" }, success: false)
    assert_includes out, "Port 443 is taken by another program on this machine"
    assert_not File.exist?(File.join(dir, "household.env"))
  end

  test "a first start that fails keeps the answers and the data, and running the installer again starts from them" do
    FileUtils.touch(File.join(@root, "unhealthy"))
    out = install!(exposure: "local", success: false)
    assert_includes out, "Household didn't start"
    assert_includes out, "Run the installer again to try once more"
    assert_equal [ "failed-start.log", "household.env" ], Dir.children(dir).sort
    assert_includes calls("docker"), "compose --progress quiet -f #{dir}/compose.yml --env-file #{dir}/household.env down --remove-orphans"
    password = env_file.fetch("POSTGRES_PASSWORD")

    busy 8080
    out = install!(exposure: "local")
    assert_includes out, "The answers and the data of an earlier installation are in #{dir}"
    assert_includes out, "Port 8080 is taken by another program on this machine."
    assert_match(%r{Open   http://localhost:8081$}, out)
    assert_equal [ password, "8081" ], env_file.values_at("POSTGRES_PASSWORD", "PORT")
    assert File.executable?(File.join(dir, "household"))
  end

  test "--reset uninstalls first, asking what goes as an uninstall does, then installs from the beginning" do
    install!(exposure: "network", env: { "HOUSEHOLD_HOST" => "192.168.1.20" })
    password = env_file.fetch("POSTGRES_PASSWORD")
    out = at_a_terminal(SCRIPT, "--reset", "--from", @release, answers: [ "", "", "", "", "household", "1", "n" ])
    assert_includes out, "Household is installed in #{dir}: what people saved in it goes too, unless you keep the data."
    assert_includes out, "This removes the containers, the data and the images."
    assert_includes calls("docker"), "compose --progress quiet -f #{dir}/compose.yml --env-file #{dir}/household.env down -v --remove-orphans"
    assert_match(%r{Open   \S*http://localhost:8080}, out)
    assert_equal "local", env_file.fetch("EXPOSURE")
    assert_not_equal password, env_file.fetch("POSTGRES_PASSWORD")
  end

  test "--reset after a first start that failed: the release's compose.yml names what to remove, and --yes never removes the data" do
    FileUtils.touch(File.join(@root, "unhealthy"))
    install!(exposure: "local", success: false)
    env = File.read(File.join(dir, "household.env"))
    out = run_script(SCRIPT, "--yes", "--reset", "--from", @release, env: { "HOUSEHOLD_EXPOSURE" => "local" }, success: false)
    assert_includes out, "Left as it is."
    assert_equal env, File.read(File.join(dir, "household.env"))

    out = run_script(SCRIPT, "--yes", "--reset", "--keep-data", "--from", @release, env: { "HOUSEHOLD_EXPOSURE" => "local" })
    assert_includes calls("docker"), "compose --progress quiet -f #{dir}/compose.yml --env-file #{dir}/household.env down --remove-orphans"
    assert_includes out, "The answers and the data of an earlier installation are in #{dir}"
    assert_equal env, File.read(File.join(dir, "household.env"))
    assert_not File.exist?(File.join(dir, "failed-start.log"))
  end

  test "a second run leaves an installation as it is" do
    install!(exposure: "local")
    before = File.read(File.join(dir, "household.env"))
    out = install!(exposure: "network", env: { "HOUSEHOLD_HOST" => "box.home" })
    assert_includes out, "installed in #{dir} already"
    assert_equal before, File.read(File.join(dir, "household.env"))
  end

  test "once someone has an account there is no code to give" do
    FileUtils.touch(File.join(@root, "account"))
    out = install!(exposure: "local")
    assert_includes out, "someone has an account already"
    assert_no_match(/Code   /, out)
  end

  test "the release is downloaded and checked against its SHA256SUMS before anything is installed" do
    sums = Dir.chdir(@release) { `sha256sum compose.yml install.sh release.json` }
    File.write(File.join(@release, "SHA256SUMS"), sums)
    out = install!(exposure: "local", from: nil)
    assert_match(/Code   #{CODE}$/, out)
    assert_equal(%w[release.json compose.yml install.sh SHA256SUMS], calls("curl").map { _1.split("/").last })

    FileUtils.rm_rf(dir)
    File.write(File.join(@release, "compose.yml"), "services: {}\n")
    out = install!(exposure: "local", from: nil, success: false)
    assert_includes out, "don't match its SHA256SUMS"
    assert_not File.exist?(dir)
  end

  test "the household command: a new setup code while nobody has an account, refused after" do
    install!(exposure: "local")
    out = household("setup-code")
    assert_match(/Code   #{CODE}$/, out)
    FileUtils.touch(File.join(@root, "account"))
    out = household("setup-code", success: false)
    assert_includes out, "Someone has an account already"
  end

  test "a nightly backup unless told not to, in the crontab once however often it is installed" do
    install!(exposure: "local")
    line = "30 3 * * * #{dir}/household backup > #{dir}/backups/last.log 2>&1 # household backup #{dir}"
    assert_equal [ line ], File.readlines(File.join(@root, "crontab"), chomp: true)

    FileUtils.rm_rf(dir)
    File.write(File.join(@root, "crontab"), "0 1 * * * something else\n")
    install!(exposure: "local", env: { "HOUSEHOLD_BACKUPS" => "no" })
    assert_equal [ "0 1 * * * something else" ], File.readlines(File.join(@root, "crontab"), chomp: true)
  end

  test "a backup: the database and the files, readable by their owner alone, the newest seven kept" do
    install!(exposure: "local")
    8.times { |day| FileUtils.mkdir_p(File.join(dir, "backups", "2026100#{day}T033000Z-2026.10.1")) }
    out = household("backup")
    backup = out[/Backed up into (.+)$/, 1]
    assert_match(%r{/backups/\d{8}T\d{6}Z-2026\.11\.1\z}, backup)
    assert_equal "the database\n", File.read(File.join(backup, "database.dump"))
    assert_equal "the files\n", File.read(File.join(backup, "files.tar.gz"))
    assert_equal "100600", File.stat(File.join(backup, "database.dump")).mode.to_s(8)
    assert_equal "40700", File.stat(backup).mode.to_s(8)
    kept = Dir.children(File.join(dir, "backups")).select { File.directory?(File.join(dir, "backups", _1)) }.sort
    assert_equal 7, kept.size
    assert_not_includes kept, "20261000T033000Z-2026.10.1", "the oldest goes"
  end

  test "an update: backed up first, the app stopped before the new version starts, the old one kept for a rollback" do
    install!(exposure: "local")
    assert_includes household("update", "--from", @release), "Household 2026.11.1 is the newest release."

    newer = next_release
    out = household("update", "--from", newer)
    assert_includes out, "Household 2026.11.1 → 2026.11.2"
    assert_includes out, "Household 2026.11.2 is running."
    assert_equal "2026.11.2", JSON.parse(File.read(File.join(dir, "release.json"))).fetch("version")
    assert_equal "2026.11.1", JSON.parse(File.read(File.join(dir, "previous", "release.json"))).fetch("version")
    assert File.directory?(File.read(File.join(dir, "previous", "backup")).chomp)

    files = "-f #{dir}/compose.yml --env-file #{dir}/household.env"
    update = calls("docker").drop_while { !_1.include?("pg_dump") }.grep(/ -f /)
    assert_equal [ "compose #{files} exec -T db pg_dump -U household -Fc household_production",
                   "compose --progress quiet #{files} run --rm --no-deps -T --entrypoint tar web czf - -C /rails storage secrets",
                   "compose --progress quiet #{files} pull", "compose --progress quiet #{files} stop web job",
                   "compose --progress quiet #{files} up -d --wait --wait-timeout 300" ], update
  end

  test "an update that doesn't come up healthy puts the old version back with the data from before it" do
    install!(exposure: "local")
    FileUtils.touch(File.join(@root, "unhealthy"))
    out = household("update", "--from", next_release, success: false)
    assert_includes out, "putting 2026.11.1 back"
    assert_includes out, "Household 2026.11.1 is running again."
    assert_equal "2026.11.1", JSON.parse(File.read(File.join(dir, "release.json"))).fetch("version")
    assert(calls("docker").any? { _1.include?("dropdb -U household --if-exists --force household_production") })
    assert(calls("docker").any? { _1.end_with?("exec -T db pg_restore -U household --no-owner -d household_production") })
  end

  test "what loses data waits for its word typed back, which --yes never types" do
    install!(exposure: "local")
    assert_includes household("rollback", success: false), "There is no update to undo here."
    household("update", "--from", next_release)
    assert_includes household("rollback", "--yes", success: false), "Left as it is."
    assert_includes household("uninstall", success: false), "Left as it is."
    assert_includes household("uninstall", "--yes", "--keep-data", "--remove-backups", success: false), "Left as it is."
    assert_includes household("restore", File.join(dir, "backups"), success: false), "Left as it is."
    assert_path_exists File.join(dir, "household.env")
    assert_empty calls("docker").grep(/ down /)
  end

  test "an uninstall asks what goes: the data and the images by default, after the directory's name; the backups and the crontab's other lines stay" do
    File.write(File.join(@root, "crontab"), "0 1 * * * something else\n")
    install!(exposure: "tailscale")
    household("update", "--from", next_release)
    out = household_at_a_terminal("uninstall", answers: [ "", "", "", "household" ])
    assert_includes out, "Household 2026.11.2 in #{dir}"
    assert_includes out, "The data: the database, the files and the secrets, in its three volumes? [Y/n]"
    assert_includes out, "The backups in backups/ (1 backup,"
    assert_includes out, "The images it pulled? [Y/n]"
    assert_includes out, "This removes the containers, the data and the images."
    assert_includes out, "Household is gone from this machine."
    assert_includes out, "The backups stay in #{dir}/backups."
    assert_includes out, "Tailscale still serves https://box.tail1234.ts.net: sudo tailscale serve reset stops it."

    files = "-f #{dir}/compose.yml --env-file #{dir}/household.env"
    uninstall = calls("docker").drop_while { !_1.include?(" down ") }
    assert_equal [ "compose --progress quiet #{files} down -v --remove-orphans", "compose #{files} config --images",
                   "image rm #{IMAGE}", "image rm postgres:16" ], uninstall
    assert_equal [ "0 1 * * * something else" ], File.readlines(File.join(@root, "crontab"), chomp: true)
    assert_equal [ "backups" ], Dir.children(dir)
    assert_equal 1, Dir.children(File.join(dir, "backups")).size
  end

  test "an uninstall that keeps the data loses nothing, so --yes suffices, and installing again starts with it" do
    install!(exposure: "network", env: { "HOUSEHOLD_HOST" => "192.168.1.20" })
    env = File.read(File.join(dir, "household.env"))
    out = household("uninstall", "--yes", "--keep-data", "--keep-images")
    assert_includes out, "This removes the containers."
    assert_includes out, "The data stays in its three volumes, with #{dir}/household.env"
    assert_equal [ "backups", "household.env" ], Dir.children(dir).sort
    assert_includes calls("docker"), "compose --progress quiet -f #{dir}/compose.yml --env-file #{dir}/household.env down --remove-orphans"
    assert_empty calls("docker").grep(/image rm/)

    out = install!(exposure: "local")
    assert_includes out, "The answers and the data of an earlier installation are in #{dir}: Household starts again with them."
    assert_includes out, "Open   http://192.168.1.20:8080"
    assert_equal env, File.read(File.join(dir, "household.env"))
    assert_equal File.read(SCRIPT), File.read(File.join(dir, "household"))
  end

  test "an uninstall told to remove the backups leaves nothing but what else was in the directory" do
    install!(exposure: "local")
    household("backup")
    out = household_at_a_terminal("uninstall", "--remove-backups", answers: [ "", "", "household" ])
    assert_includes out, "This removes the containers, the data, the backups and the images."
    assert_not File.exist?(dir)

    install!(exposure: "local")
    File.write(File.join(dir, "notes.txt"), "mine")
    out = household_at_a_terminal("uninstall", "--remove-backups", answers: [ "", "", "household" ])
    assert_includes out, "#{dir} stays, with what else is in it."
    assert_equal [ "notes.txt" ], Dir.children(dir)
  end

  test "config: how people reach it asked again, the database's password and a line of one's own kept" do
    install!(exposure: "local")
    File.write(File.join(dir, "household.env"), "UPLOADS=off\n", mode: "a")
    password = env_file.fetch("POSTGRES_PASSWORD")
    out = household("config", "--yes", env: { "HOUSEHOLD_EXPOSURE" => "proxy", "HOUSEHOLD_HOST" => "home.example.com" })
    assert_includes out, "Household is at https://home.example.com"
    assert_equal [ password, "off", "proxy", "home.example.com", "on" ], env_file.values_at("POSTGRES_PASSWORD", "UPLOADS", "EXPOSURE", "APP_HOST", "FORCE_SSL")
    assert_equal(1, File.readlines(File.join(dir, "household.env")).count { _1.start_with?("APP_HOST=") })
  end

  private

  # The same release, one version on.
  def next_release
    newer = File.join(@root, "newer")
    FileUtils.cp_r(@release, newer)
    File.write(File.join(newer, "release.json"), %({\n  "version": "2026.11.2",\n  "stopped_migrations": []\n}\n))
    newer
  end

  def household(*args, **options) = run_script(File.join(dir, "household"), *args, **options)

  def household_at_a_terminal(*args, answers:) = at_a_terminal(File.join(dir, "household"), *args, answers: answers)

  # A script on a terminal of its own, each answer typed to its question in
  # turn; an empty answer takes the default.
  def at_a_terminal(script, *args, answers:)
    out = +""
    PTY.spawn(environment, "sh", script, *args) do |reader, writer, pid|
      answers.each { |answer| writer.puts(answer) }
      begin
        out << reader.readpartial(4096) while true
      rescue EOFError, Errno::EIO
        # A terminal whose other side has gone answers with EIO on Linux: the end of its output.
      end
      _, status = Process.wait2(pid)
      assert_predicate status, :success?, out
    end
    out
  end

  def dir = File.join(@home, "household")

  def busy(*ports) = File.write(File.join(@root, "busy"), ports.join("\n") + "\n", mode: "a")

  def fake(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\necho \"$*\" >> \"#{@root}/#{name}.calls\"\n#{body}\n")
    File.chmod(0o755, path)
  end

  def calls(name) = File.exist?(file = File.join(@root, "#{name}.calls")) ? File.readlines(file, chomp: true) : []

  def install!(exposure:, env: {}, from: @release, success: true)
    args = [ "--yes", *(from ? [ "--from", from ] : []) ]
    run_script(SCRIPT, *args, env: env.merge("HOUSEHOLD_EXPOSURE" => exposure), success: success)
  end

  def run_script(script, *args, env: {}, success: true)
    out, status = Open3.capture2e(environment(env), "sh", script, *args, unsetenv_others: true, in: File::NULL)
    assert_equal success, status.success?, out
    out
  end

  def environment(env = {})
    { "PATH" => "#{@bin}:/usr/bin:/bin", "HOME" => @home, "HOUSEHOLD_REPOSITORY" => "owner/household" }.merge(env)
  end

  def env_file = File.readlines(File.join(dir, "household.env"), chomp: true).grep(/\A[A-Z_]+=/).to_h { _1.split("=", 2) }
end
