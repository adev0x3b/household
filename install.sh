#!/bin/sh
# Household's installer, and the `household` command it leaves in the
# installation's directory (docs/self-hosting.md). It needs Docker and
# nothing else, asks only what a browser can't (where the files go and how
# people reach the app), and ends by printing the address and the one-time
# code the setup page asks for. POSIX sh, so it runs wherever Docker does.
#
#   sh install.sh                  install the newest release
#   sh install.sh --yes            take every default, and the answers below from the environment
#   ~/household/household help     what the command does once installed
set -eu

REPOSITORY=${HOUSEHOLD_REPOSITORY:-adev0x3b/household}
COMPOSE_TIMEOUT=300
BACKUPS_KEPT=7

usage() {
  cat <<'EOF'
Usage: sh install.sh [--yes] [--version 2026.11.1] [--from <directory>] [--reset]
       household <command>

Commands, run from the installation's directory:
  update [--version V]  the newest release (or V), backed up first, put back if it fails
  rollback              the version before the last update, with the data from before it
  backup                the database, the secrets and the files, into backups/
  restore <backup>      a backup put back, over what is there now
  config                how people reach it, asked again
  setup-code            a new code for the setup page, while nobody has an account
  status                what runs, and the version
  logs                  the app's log, followed (Ctrl-C stops following)
  stop, start           stop the app, start it again
  uninstall             the containers removed, and what it asks about: the data
                        (--keep-data), the backups (--remove-backups), the images (--keep-images)
  help                  this

--yes takes each default without asking; the answers that have none come
from the environment: HOUSEHOLD_DIR, HOUSEHOLD_EXPOSURE (local, network,
tailscale, cloudflare, public or proxy), HOUSEHOLD_HOST, HOUSEHOLD_PORT,
TUNNEL_TOKEN and HOUSEHOLD_BACKUPS (yes or no). What loses data is
confirmed by a word typed back, which --yes never types.
--from installs the compose.yml, release.json and install.sh found in a
directory instead of downloading a release. --reset uninstalls what an
earlier installation or a failed attempt left in the directory first,
asking what goes as uninstall does.
EOF
}

# --- Talking to the person --------------------------------------------------

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m') DIM=$(printf '\033[2m') RED=$(printf '\033[31m') RESET=$(printf '\033[0m')
else
  BOLD='' DIM='' RED='' RESET=''
fi

say() { printf '%s\n' "$*"; }
heading() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
note() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; }
die() {
  warn "$*"
  exit 1
}

ASSUME_YES=false

# Whether there is a terminal to ask, even when the script itself arrives
# on standard input.
has_terminal() {
  (exec < /dev/tty) 2> /dev/null
}

# The answer to a question, read from the terminal; the default when there
# is no terminal to ask or --yes said to take it. The default is shown in
# brackets, or the hint given in its place.
ask() {
  question=$1 default=$2 hint=${3:-$2}
  if $ASSUME_YES || ! has_terminal; then
    printf '%s\n' "$default"
    return
  fi
  if [ -n "$hint" ]; then
    printf '%s [%s] ' "$question" "$hint" > /dev/tty
  else
    printf '%s ' "$question" > /dev/tty
  fi
  IFS= read -r answer < /dev/tty || answer=''
  printf '%s\n' "${answer:-$default}"
}

# The same, without echoing what is typed.
ask_secret() {
  question=$1 default=$2
  if $ASSUME_YES || ! has_terminal; then
    printf '%s\n' "$default"
    return
  fi
  printf '%s ' "$question" > /dev/tty
  stty -echo < /dev/tty
  IFS= read -r answer < /dev/tty || answer=''
  stty echo < /dev/tty
  printf '\n' > /dev/tty
  printf '%s\n' "${answer:-$default}"
}

# Yes unless the default says no, when nobody answers.
yes_or_no() {
  question=$1 default=${2:-yes}
  case $default in
    [nN]*) hint=y/N ;;
    *) hint=Y/n ;;
  esac
  case $(ask "$question" "$default" "$hint") in
    [nN]*) return 1 ;;
    *) return 0 ;;
  esac
}

# What is about to be lost is confirmed by typing a word back, and --yes
# never types it.
typed_back() {
  question=$1 word=$2
  has_terminal || return 1
  printf '%s ' "$question" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=''
  [ "$answer" = "$word" ]
}

# --- The machine ------------------------------------------------------------

# Docker, run by the person when they may, else through sudo.
DOCKER=docker
SUDO=''

# One password prompt for everything that needs one, asked just before the
# first step that does.
need_root() {
  reason=$1
  [ "$(id -u)" = 0 ] && return
  [ -n "$SUDO" ] && return
  command -v sudo > /dev/null 2>&1 || die "This step needs root ($reason), and sudo isn't here. Run the installer as root."
  say "sudo asks for your password once: $reason."
  sudo -v || die "sudo refused."
  SUDO=sudo
}

download() {
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget > /dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "Neither curl nor wget is here to download $1."
  fi
}

sha256_check() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum -c --quiet -
  else
    shasum -a 256 -c --quiet -
  fi
}

check_docker() {
  if ! command -v docker > /dev/null 2>&1; then
    case $(uname -s) in
      Linux)
        yes_or_no "Docker isn't installed. Install it with Docker's own script (get.docker.com)?" ||
          die "Household runs in Docker: install it (https://docs.docker.com/engine/install/) and run this again."
        need_root "installing Docker"
        download https://get.docker.com "$WORK/get-docker.sh"
        $SUDO sh "$WORK/get-docker.sh"
        $SUDO systemctl enable --now docker > /dev/null 2>&1 || true
        ;;
      *) die "Household runs in Docker: install Docker Desktop (https://www.docker.com/products/docker-desktop/), start it, and run this again." ;;
    esac
  fi
  if ! docker info > /dev/null 2>&1; then
    need_root "Docker answers only to root here"
    DOCKER="$SUDO docker"
    $DOCKER info > /dev/null 2>&1 || die "Docker isn't running: start it (sudo systemctl start docker) and run this again."
    note "Tip: sudo usermod -aG docker $(id -un), then log in again, lets you run Docker without sudo."
  fi
  $DOCKER compose version > /dev/null 2>&1 || die "Docker Compose isn't here: install the compose plugin (https://docs.docker.com/compose/install/linux/)."
  say "Docker $($DOCKER version --format '{{.Server.Version}}') ✓  Compose $($DOCKER compose version --short) ✓"
}

machine_zone() {
  zone=$(timedatectl show -p Timezone --value 2> /dev/null || true)
  [ -n "$zone" ] || zone=$(cat /etc/timezone 2> /dev/null || true)
  [ -n "$zone" ] || zone=$(readlink /etc/localtime 2> /dev/null | sed -n 's|.*/zoneinfo/||p')
  printf '%s\n' "${zone:-UTC}"
}

machine_address() {
  address=$(hostname -I 2> /dev/null | cut -d' ' -f1)
  printf '%s\n' "${address:-$(hostname)}"
}

# --- The release ------------------------------------------------------------

# The release's compose.yml, release.json and install.sh into $WORK:
# downloaded and checked against its SHA256SUMS, or taken from a directory
# (--from).
fetch_release() {
  if [ -n "$FROM" ]; then
    cp "$FROM/compose.yml" "$FROM/release.json" "$FROM/install.sh" "$WORK/" || die "$FROM lacks compose.yml, release.json or install.sh."
    return
  fi
  if [ -n "$VERSION" ]; then
    base="https://github.com/$REPOSITORY/releases/download/v$VERSION"
  else
    base="https://github.com/$REPOSITORY/releases/latest/download"
  fi
  for file in release.json compose.yml install.sh SHA256SUMS; do
    download "$base/$file" "$WORK/$file" || die "Couldn't download $base/$file."
  done
  (cd "$WORK" && grep -E '  (compose\.yml|release\.json|install\.sh)$' SHA256SUMS | sha256_check) ||
    die "The release's files don't match its SHA256SUMS: nothing was installed."
}

release_field() {
  sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" "$2" | head -n 1
}

# --- How people reach it ----------------------------------------------------

show_exposures() {
  say "  1  Only this computer"
  say "  2  Devices on my home network, over plain HTTP"
  note "       (the browser works; phones can't install it, get notifications or scan barcodes)"
  say "  3  Through Tailscale: HTTPS, only your own devices            (recommended at home)"
  say "  4  Through a Cloudflare Tunnel: HTTPS, from anywhere"
  say "  5  At a public address, with a certificate Household gets itself (ports 80 and 443)"
  say "  6  Behind my own reverse proxy"
}

# Sets the lines of household.env that say where the app answers, and
# ADDRESS, what to open. Each answer only changes these few.
ask_exposure() {
  heading "How will people reach it?"
  if $ASSUME_YES; then
    choice=${HOUSEHOLD_EXPOSURE:-local}
    say "$choice"
  else
    show_exposures
    choice=$(ask ">" "${HOUSEHOLD_EXPOSURE:-${EXPOSURE:-1}}")
  fi

  BIND=127.0.0.1 PORT=${HOUSEHOLD_PORT:-${PORT:-8080}} TLS_PORT=${TLS_PORT:-8443} FORCE_SSL=on APP_HOST='' TLS_DOMAIN='' TUNNEL='' PROFILES=''
  case $choice in
    1 | local)
      EXPOSURE=local FORCE_SSL=off APP_HOST=localhost
      ;;
    2 | network)
      EXPOSURE=network BIND=0.0.0.0 FORCE_SSL=off
      APP_HOST=$(ask "The name or IP the others will type (only that one opens it):" "${HOUSEHOLD_HOST:-$(machine_address)}")
      ;;
    3 | tailscale)
      EXPOSURE=tailscale
      command -v tailscale > /dev/null 2>&1 ||
        die "Tailscale isn't on this machine: install it (https://tailscale.com/download/linux), run 'sudo tailscale up', and run this again."
      name=$(tailscale status --json --peers=false 2> /dev/null | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -n 1)
      APP_HOST=$(ask "This machine's name on your tailnet:" "${HOUSEHOLD_HOST:-$name}")
      ;;
    4 | cloudflare)
      EXPOSURE=cloudflare PROFILES=cloudflare
      TUNNEL=$(ask_secret "The tunnel's token:" "${TUNNEL_TOKEN:-}")
      APP_HOST=$(ask "The hostname you gave the tunnel:" "${HOUSEHOLD_HOST:-}")
      [ -n "$TUNNEL" ] || die "A Cloudflare Tunnel needs its token (Zero Trust → Networks → Tunnels → your tunnel)."
      ;;
    5 | public)
      EXPOSURE=public BIND=0.0.0.0 PORT=80 TLS_PORT=443
      APP_HOST=$(ask "The public name, already pointing at this machine:" "${HOUSEHOLD_HOST:-}")
      TLS_DOMAIN=$APP_HOST
      ;;
    6 | proxy)
      EXPOSURE=proxy
      APP_HOST=$(ask "The name your proxy serves it at:" "${HOUSEHOLD_HOST:-}")
      PORT=$(ask "The port on 127.0.0.1 your proxy forwards to:" "$PORT")
      ;;
    *) die "Not one of the six: $choice" ;;
  esac
  [ -n "$APP_HOST" ] || die "Household needs the name people will use to reach it."
  case $APP_HOST in
    */* | *:* | *' '*) die "A name without a scheme, a port or a path, please: $APP_HOST" ;;
  esac
  free_ports
  ADDRESS=$(address_of "$EXPOSURE" "$APP_HOST" "$PORT")
}

# --- Ports ------------------------------------------------------------------

# Ports this installation holds itself while it runs, which count as free
# when it is asked again how people reach it.
OWN_PORTS=''

# PORT and TLS_PORT, moved off any port another program holds, since Docker
# would refuse to start the app there. A public address needs 80 and 443
# themselves. Elsewhere the person picks another port for the app, and the
# HTTPS port, which nothing reaches unless the address is public, moves by
# itself.
free_ports() {
  if [ "$EXPOSURE" = public ]; then
    for wanted in 80 443; do
      port_free "$wanted" ||
        die "Port $wanted is taken by another program on this machine, and a certificate of Household's own needs 80 and 443. Stop that program and run this again, or choose 6 and let it forward to Household."
    done
    return
  fi
  until port_free "$PORT"; do
    say "Port $PORT is taken by another program on this machine."
    PORT=$(ask "Which port should Household use?" "$(free_port_after "$PORT")")
    valid_port "$PORT" || die "A port is a number from 1 to 65535: $PORT"
  done
  until [ "$TLS_PORT" != "$PORT" ] && port_free "$TLS_PORT"; do
    TLS_PORT=$(free_port_after "$TLS_PORT")
  done
}

valid_port() {
  case $1 in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_free() {
  case " $OWN_PORTS " in
    *" $1 "*) return 0 ;;
  esac
  ! port_taken "$1"
}

# The first free port after $1.
free_port_after() {
  candidate=$(($1 + 1))
  while [ "$candidate" -le 65535 ]; do
    if [ "$candidate" != "$PORT" ] && port_free "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
    candidate=$((candidate + 1))
  done
  die "No free port after $1 on this machine."
}

# Whether a program on this machine listens on a TCP port, asked of
# whichever of ss (Linux), lsof (macOS) and netstat is here. With none of
# them it can't tell and says no, and Docker's own refusal follows.
port_taken() {
  if command -v ss > /dev/null 2>&1; then
    ss -Hltn "sport = :$1" 2> /dev/null | grep -q .
  elif command -v lsof > /dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN > /dev/null 2>&1
  elif command -v netstat > /dev/null 2>&1; then
    netstat -an 2> /dev/null | grep -i listen | grep -Eq "[.:]$1[[:space:]]"
  else
    return 1
  fi
}

write_env() {
  password=$(od -An -tx1 -N24 /dev/urandom | tr -d ' \n')
  (
    umask 077
    cat > "$DIR/household.env" <<EOF
# This installation's answers to install.sh, read by compose.yml. Readable
# by you alone: it holds the database's password, which lives in the db
# volume from now on and must stay as it is.
POSTGRES_PASSWORD=$password
TIME_ZONE=$ZONE
EOF
  )
  write_exposure
}

# The exposure's lines, changed in place, so a line the person added
# themselves stays.
write_exposure() {
  set_env EXPOSURE "$EXPOSURE"
  set_env APP_HOST "$APP_HOST"
  set_env BIND "$BIND"
  set_env PORT "$PORT"
  set_env TLS_PORT "$TLS_PORT"
  set_env FORCE_SSL "$FORCE_SSL"
  set_env TLS_DOMAIN "$TLS_DOMAIN"
  set_env TUNNEL_TOKEN "$TUNNEL"
  set_env COMPOSE_PROFILES "$PROFILES"
}

set_env() {
  file="$DIR/household.env"
  (
    umask 077
    KEY=$1 VALUE=$2 awk '
      index($0, ENVIRON["KEY"] "=") == 1 { print ENVIRON["KEY"] "=" ENVIRON["VALUE"]; done = 1; next }
      { print }
      END { if (!done) print ENVIRON["KEY"] "=" ENVIRON["VALUE"] }
    ' "$file" > "$file.new"
  )
  mv "$file.new" "$file"
}

# --- Running it -------------------------------------------------------------

compose() {
  progress=''
  if [ "${1:-}" = --progress ]; then
    progress="--progress $2"
    shift 2
  fi
  # shellcheck disable=SC2086 # $progress is two words or none
  $DOCKER compose $progress -f "$DIR/compose.yml" --env-file "$DIR/household.env" "$@"
}

env_value() {
  sed -n "s/^$1=//p" "$DIR/household.env" | tail -n 1
}

# Fails rather than stops the script, so that the installer can leave a
# first start that failed ready to be tried again.
start_app() {
  say "Pulling household $(release_field version "$DIR/release.json") …"
  compose --progress quiet pull || return 1
  say "Starting (the first boot migrates the database, a minute or two) …"
  compose --progress quiet up -d --wait --wait-timeout "$COMPOSE_TIMEOUT" || return 1
  say "Ready."
}

# A first start that failed leaves the answers and the data, as an uninstall
# that keeps the data does, so running the installer again starts from them
# and asks again for a port another program has taken since.
first_start_failed() {
  compose logs --no-color > "$DIR/failed-start.log" 2>&1 || true
  compose --progress quiet down --remove-orphans > /dev/null 2>&1 || true
  rm -f "$DIR/compose.yml" "$DIR/release.json"
  die "Household didn't start: Docker's reason is above, the app's log in $DIR/failed-start.log. Run the installer again to try once more with the same answers, or with --reset to start from the beginning."
}

installed_version() {
  release_field version "$DIR/release.json"
}

# Where people open it, from what household.env says.
address() {
  address_of "$(env_value EXPOSURE)" "$(env_value APP_HOST)" "$(env_value PORT)"
}

address_of() {
  case $1 in
    local) printf 'http://localhost:%s\n' "$3" ;;
    network) printf 'http://%s:%s\n' "$2" "$3" ;;
    *) printf 'https://%s\n' "$2" ;;
  esac
}

serve_on_tailnet() {
  need_root "Tailscale serves the app over HTTPS on your tailnet"
  $SUDO tailscale serve --bg --https=443 "http://127.0.0.1:$PORT" > /dev/null ||
    die "tailscale serve refused: turn on HTTPS certificates for your tailnet (https://login.tailscale.com/admin/dns), then run: sudo tailscale serve --bg --https=443 http://127.0.0.1:$PORT"
}

# The app makes the code and keeps only its digest; it says 3 once someone
# has an account, since the setup page is gone from then on. The app logs to
# standard output, where the code comes too, so it runs quiet below warn.
setup_code() {
  errors="$WORK/setup-code.err"
  if code=$(compose exec -T -e RAILS_LOG_LEVEL=warn web bin/rails setup:code 2> "$errors"); then
    printf '%s\n' "$code"
    return 0
  else
    status=$?
  fi
  [ "$status" = 3 ] && return 3
  cat "$errors" >&2
  die "The app couldn't make a setup code."
}

# --- The commands -------------------------------------------------------------

install() {
  fetch_release
  version=$(release_field version "$WORK/release.json")
  heading "Household $version"
  check_docker

  DIR=$(ask "Where should Household keep its files?" "${HOUSEHOLD_DIR:-$HOME/household}")
  case $DIR in "~"*) DIR="$HOME${DIR#\~}" ;; esac
  if $START_OVER; then start_over; fi
  # The household command is put in place once the app has started, so a
  # directory without it holds at most a start that didn't finish.
  if [ -f "$DIR/household" ]; then
    say "Household is installed in $DIR already, and was left as it is: $DIR/household status shows it, and --reset starts over."
    exit 0
  fi
  mkdir -p "$DIR"
  DIR=$(cd "$DIR" && pwd)

  # An uninstall that kept the data, or a first start that failed, left
  # household.env, whose password opens the database volume: the same
  # answers start it again with what it held, on ports free now.
  kept=false
  if [ -f "$DIR/household.env" ]; then
    kept=true
    say "The answers and the data of an earlier installation are in $DIR: Household starts again with them."
    EXPOSURE=$(env_value EXPOSURE) APP_HOST=$(env_value APP_HOST) PORT=$(env_value PORT) TLS_PORT=$(env_value TLS_PORT)
    free_ports
    set_env PORT "$PORT"
    set_env TLS_PORT "$TLS_PORT"
    ADDRESS=$(address)
  else
    ask_exposure
    ZONE=$(machine_zone)
  fi
  say ""
  nightly=yes
  yes_or_no "Back up every night (the database, the secrets and the files, the newest $BACKUPS_KEPT kept)?" "${HOUSEHOLD_BACKUPS:-}" || nightly=no

  cp "$WORK/compose.yml" "$WORK/release.json" "$DIR/"
  $kept || write_env
  say ""
  start_app || first_start_failed
  install_command
  if [ "$EXPOSURE" = tailscale ]; then serve_on_tailnet; fi
  if [ "$nightly" = yes ]; then back_up_nightly; fi

  code=$(setup_code) || {
    say "Household is at $ADDRESS, and someone has an account already."
    exit 0
  }
  say ""
  say "  Open   $BOLD$ADDRESS$RESET"
  say "  Code   $BOLD$code$RESET"
  say ""
  say "  The setup page asks for the code once, and it works only until the first account exists."
  say "  Lost it? $DIR/household setup-code"
  case $EXPOSURE in
    cloudflare) note "  In Cloudflare, the tunnel's public hostname $APP_HOST points at http://web:80." ;;
    public) note "  The certificate comes on the first visit to $ADDRESS, once $APP_HOST points here." ;;
    proxy) note "  Your proxy forwards $APP_HOST to http://127.0.0.1:$PORT." ;;
  esac
}

# An earlier installation, or what a failed attempt left, uninstalled
# before installing again: the same questions about what goes, and the same
# word typed back before the data or the backups do.
start_over() {
  [ -f "$DIR/household.env" ] || return 0
  DIR=$(cd "$DIR" && pwd)
  if [ -f "$DIR/household" ]; then
    warn "Household is installed in $DIR: what people saved in it goes too, unless you keep the data."
  fi
  # A first start that failed took compose.yml away; the release's names
  # the same containers and volumes.
  [ -f "$DIR/compose.yml" ] || cp "$WORK/compose.yml" "$DIR/"
  uninstall
  say ""
}

# The command people use afterwards is the release's installer, kept beside
# what it installed: the copy checked against the release, whichever way
# this one arrived.
install_command() {
  replace_command "$WORK/install.sh"
}

# Moved into place rather than written over, since the shell running an
# update is still reading the old file as it goes.
replace_command() {
  cp "$1" "$DIR/household.new"
  chmod 755 "$DIR/household.new"
  mv "$DIR/household.new" "$DIR/household"
}

in_installation() {
  DIR=$(cd "$(dirname "$0")" && pwd)
  [ -f "$DIR/household.env" ] || die "No installation here: $DIR has no household.env."
  docker info > /dev/null 2>&1 || DOCKER="sudo docker"
}

command_setup_code() {
  in_installation
  code=$(setup_code) || die "Someone has an account already, so there is no setup page to open."
  say "Code   $BOLD$code$RESET"
  note "It replaces any code made before."
}

command_status() {
  in_installation
  say "Household $(installed_version) in $DIR, at $(address)"
  compose ps --all --format 'table {{.Service}}\t{{.Status}}'
}

# --- Backups ----------------------------------------------------------------

# The database and the two volumes beside it, in a directory of their own
# under backups/, named by when and which version; prints its path. The
# secrets go with the dump because the dump is unreadable in part without
# them, and a backup is kept readable by its owner alone for the same reason.
back_up() (
  umask 077
  target="$DIR/backups/$(date -u +%Y%m%dT%H%M%SZ)-$(installed_version)"
  mkdir -p "$target"
  compose --progress quiet up -d --wait db
  compose exec -T db pg_dump -U household -Fc household_production > "$target/database.dump"
  compose --progress quiet run --rm --no-deps -T --entrypoint tar web czf - -C /rails storage secrets > "$target/files.tar.gz"
  prune_backups
  printf '%s\n' "$target"
)

prune_backups() {
  count=$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)
  [ "$count" -gt "$BACKUPS_KEPT" ] || return 0
  find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d | sort | head -n "$((count - BACKUPS_KEPT))" | while IFS= read -r old; do
    rm -rf "$old"
  done
}

# The app stopped, its files and its database replaced by a backup's.
put_back() {
  backup=$1
  if [ ! -f "$backup/database.dump" ] || [ ! -f "$backup/files.tar.gz" ]; then
    die "$backup isn't a backup: it has no database.dump and files.tar.gz."
  fi
  compose --progress quiet stop web job
  compose --progress quiet run --rm --no-deps -T --entrypoint sh web -c 'rm -rf /rails/storage/* /rails/secrets/* && tar xzf - -C /rails' < "$backup/files.tar.gz"
  compose --progress quiet up -d --wait db
  compose exec -T db sh -c 'dropdb -U household --if-exists --force household_production && createdb -U household household_production'
  compose exec -T db pg_restore -U household --no-owner -d household_production < "$backup/database.dump"
}

# A line in the crontab of whoever runs Docker here, replaced on a new
# install in the same directory rather than added twice.
back_up_nightly() {
  command -v crontab > /dev/null 2>&1 || {
    warn "cron isn't here, so nothing backs up by itself: run $DIR/household backup yourself, or from a timer."
    return 0
  }
  { crontab_without_backup_line
    printf '30 3 * * * %s backup > %s 2>&1 %s\n' "$DIR/household" "$DIR/backups/last.log" "# household backup $DIR"
  } | crontab_of_docker_user -
  mkdir -p "$DIR/backups"
  say "Backs up every night at 03:30 into $DIR/backups."
}

crontab_without_backup_line() {
  crontab_of_docker_user -l 2> /dev/null | grep -vF "# household backup $DIR" || true
}

# The backup line runs the household command, which runs Docker, so it lives
# in root's crontab where Docker answers only to root.
crontab_of_docker_user() {
  if [ "$DOCKER" = docker ]; then
    crontab "$@"
  else
    ${SUDO:-sudo} crontab "$@"
  fi
}

# --- Everyday commands -------------------------------------------------------

command_backup() {
  in_installation
  say "Backing up Household $(installed_version) …"
  say "Backed up into $(back_up)"
}

command_restore() {
  in_installation
  backup=${1:?restore needs a backup, such as $DIR/backups/<when>-<version>}
  backup=$(cd "$backup" && pwd)
  say "This replaces everything Household holds now with $backup."
  typed_back "Type restore to go on:" restore || die "Left as it is."
  put_back "$backup"
  compose --progress quiet up -d --wait --wait-timeout "$COMPOSE_TIMEOUT" ||
    die "Household didn't come up healthy after the restore. What it said: $DIR/household logs"
  say "Restored from $backup."
}

# A new release: checked, backed up, the app stopped before the new
# version migrates so a migration never runs beside the version before it,
# and the old one put back with its data if the new one doesn't come up.
command_update() {
  in_installation
  fetch_release
  old=$(installed_version)
  new=$(release_field version "$WORK/release.json")
  if [ "$old" = "$new" ]; then
    say "Household $old is the newest release."
    return 0
  fi
  heading "Household $old → $new"
  note "What's new: https://github.com/$REPOSITORY/releases/tag/v$new"
  if ! grep -q '"stopped_migrations": *\[ *\]' "$WORK/release.json"; then
    seconds=$(sed -n 's/.*"downtime_seconds": *\([0-9][0-9]*\).*/\1/p' "$WORK/release.json")
    say "Its migrations need the app stopped: Household is away for ${seconds:+about $seconds seconds, }the time they take."
  fi
  yes_or_no "Update now?" || return 0

  say "Backing up first …"
  before=$(back_up)
  rm -rf "$DIR/previous"
  mkdir "$DIR/previous"
  cp "$DIR/compose.yml" "$DIR/release.json" "$DIR/household" "$DIR/previous/"
  printf '%s\n' "$before" > "$DIR/previous/backup"
  cp "$WORK/compose.yml" "$WORK/release.json" "$DIR/"

  say "Pulling household $new …"
  compose --progress quiet pull
  compose --progress quiet stop web job
  say "Starting $new …"
  if compose --progress quiet up -d --wait --wait-timeout "$COMPOSE_TIMEOUT"; then
    install_command
    say "Household $new is running. $DIR/household rollback goes back to $old."
  else
    warn "Household $new didn't come up healthy: putting $old back, with the data from before the update."
    compose logs --no-color web > "$before/failed-update.log" 2>&1 || true
    go_back
    die "Household $old is running again. $new's log is in $before/failed-update.log"
  fi
}

go_back() {
  before=$(cat "$DIR/previous/backup")
  cp "$DIR/previous/compose.yml" "$DIR/previous/release.json" "$DIR/"
  put_back "$before"
  compose --progress quiet up -d --wait --wait-timeout "$COMPOSE_TIMEOUT" ||
    die "The old version didn't come up either. What it said: $DIR/household logs"
}

command_rollback() {
  in_installation
  [ -f "$DIR/previous/backup" ] || die "There is no update to undo here."
  old=$(release_field version "$DIR/previous/release.json")
  say "This goes back to Household $old with its data from before the update: what was written since is lost."
  typed_back "Type rollback to go on:" rollback || die "Left as it is."
  go_back
  replace_command "$DIR/previous/household"
  rm -rf "$DIR/previous"
  say "Household $old is running."
}

command_config() {
  in_installation
  EXPOSURE=$(env_value EXPOSURE)
  OWN_PORTS="$(env_value PORT) $(env_value TLS_PORT)"
  # The ports chosen before stay, unless they were a public address's own.
  if [ "$EXPOSURE" != public ]; then PORT=$(env_value PORT) TLS_PORT=$(env_value TLS_PORT); fi
  was=$EXPOSURE profiles_before=$(env_value COMPOSE_PROFILES)
  ask_exposure
  write_exposure
  if [ "$profiles_before" = cloudflare ] && [ -z "$PROFILES" ]; then
    COMPOSE_PROFILES=cloudflare compose --progress quiet rm -sf cloudflared
  fi
  compose --progress quiet up -d --wait --wait-timeout "$COMPOSE_TIMEOUT" ||
    die "Household didn't come up healthy. What it said: $DIR/household logs"
  if [ "$EXPOSURE" = tailscale ]; then serve_on_tailnet; fi
  if [ "$was" = tailscale ] && [ "$EXPOSURE" != tailscale ]; then
    note "Tailscale still serves the old address: sudo tailscale serve reset stops it."
  fi
  say "Household is at $(address)"
}

# What goes is asked, or said by a flag; the containers always go. Losing
# the data or the backups waits for the directory's name typed back, so a
# script can only uninstall what loses nothing.
command_uninstall() {
  in_installation
  uninstall
}

uninstall() {
  name=$(basename "$DIR")
  version=$(installed_version 2> /dev/null)
  heading "Household${version:+ $version} in $DIR"
  if ! $ASSUME_YES && { [ -z "$REMOVE_DATA" ] || [ -z "$REMOVE_BACKUPS" ] || [ -z "$REMOVE_IMAGES" ]; }; then
    say "The containers go. What else?"
  fi
  REMOVE_DATA=$(decided "$REMOVE_DATA" "  The data: the database, the files and the secrets, in its three volumes?" yes)
  if [ -d "$DIR/backups" ]; then
    REMOVE_BACKUPS=$(decided "$REMOVE_BACKUPS" "  The backups in backups/ ($(count_backups), $(du -sh "$DIR/backups" | cut -f1))?" no)
  else
    REMOVE_BACKUPS=no
  fi
  REMOVE_IMAGES=$(decided "$REMOVE_IMAGES" "  The images it pulled?" yes)

  say ""
  say "This removes $(listed "the containers" "$REMOVE_DATA" "the data" "$REMOVE_BACKUPS" "the backups" "$REMOVE_IMAGES" "the images")."
  if [ "$REMOVE_DATA" = yes ] || [ "$REMOVE_BACKUPS" = yes ]; then
    typed_back "Type $name to go on:" "$name" || die "Left as it is."
  else
    yes_or_no "Go on?" || die "Left as it is."
  fi

  exposure=$(env_value EXPOSURE) host=$(env_value APP_HOST)
  if [ "$REMOVE_DATA" = yes ]; then
    compose --progress quiet down -v --remove-orphans
  else
    compose --progress quiet down --remove-orphans
  fi
  if command -v crontab > /dev/null 2>&1; then
    crontab_without_backup_line | crontab_of_docker_user -
  fi
  if [ "$REMOVE_IMAGES" = yes ]; then
    for image in $(compose config --images); do
      $DOCKER image rm "$image" > /dev/null 2>&1 || note "$image stays: something else on this machine uses it."
    done
  fi
  rm -rf "$DIR/compose.yml" "$DIR/release.json" "$DIR/previous" "$DIR/household" "$DIR/failed-start.log"
  if [ "$REMOVE_DATA" = yes ]; then rm -f "$DIR/household.env"; fi
  if [ "$REMOVE_BACKUPS" = yes ]; then rm -rf "$DIR/backups"; fi
  rmdir "$DIR" 2> /dev/null || true

  say "Household is gone from this machine."
  if [ "$REMOVE_DATA" = no ]; then
    say "  The data stays in its three volumes, with $DIR/household.env: sh install.sh into $DIR starts Household again with it."
  fi
  if [ -d "$DIR/backups" ]; then say "  The backups stay in $DIR/backups."; fi
  if [ -d "$DIR" ]; then say "  $DIR stays, with what else is in it."; fi
  if [ "$exposure" = tailscale ]; then
    note "  Tailscale still serves https://$host: sudo tailscale serve reset stops it."
  fi
}

count_backups() {
  count=$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  if [ "$count" = 1 ]; then say "1 backup"; else say "$count backups"; fi
}

# A yes or no already given by a flag, else asked.
decided() {
  given=$1 question=$2 default=$3
  if [ -n "$given" ]; then
    say "$given"
  elif yes_or_no "$question" "$default"; then
    say yes
  else
    say no
  fi
}

# "a, b and c" out of the first thing, then pairs of a yes or no and a thing.
listed() {
  list=$1
  shift
  while [ $# -gt 0 ]; do
    [ "$1" = yes ] && list="$list, $2"
    shift 2
  done
  case $list in
    *,*) printf '%s and %s\n' "${list%,*}" "${list##*, }" ;;
    *) printf '%s\n' "$list" ;;
  esac
}

main() {
  FROM='' VERSION='' PORT='' TLS_PORT='' START_OVER=false
  REMOVE_DATA='' REMOVE_BACKUPS='' REMOVE_IMAGES=''
  command='' argument=''
  while [ $# -gt 0 ]; do
    case $1 in
      --yes | -y) ASSUME_YES=true ;;
      --version) VERSION=${2:?--version needs a version, such as 2026.11.1}; shift ;;
      --from) FROM=$(cd "${2:?--from needs a directory}" && pwd); shift ;;
      --reset) START_OVER=true ;;
      --keep-data) REMOVE_DATA=no ;;
      --remove-backups) REMOVE_BACKUPS=yes ;;
      --keep-images) REMOVE_IMAGES=no ;;
      --help | -h | help) usage; exit 0 ;;
      -*) usage >&2; exit 2 ;;
      *)
        if [ -z "$command" ]; then
          command=$1
        elif [ "$command" = restore ] && [ -z "$argument" ]; then
          argument=$1
        else
          usage >&2
          exit 2
        fi
        ;;
    esac
    shift
  done
  if [ -z "$command" ]; then
    if [ "$(basename "$0")" = household ]; then command=status; else command=install; fi
  fi

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT

  case $command in
    install) install ;;
    update) command_update ;;
    rollback) command_rollback ;;
    backup) command_backup ;;
    restore) command_restore "$argument" ;;
    config) command_config ;;
    uninstall) command_uninstall ;;
    setup-code) command_setup_code ;;
    status) command_status ;;
    logs) in_installation; compose logs -f --tail 100 web job ;;
    stop) in_installation; compose stop ;;
    start) in_installation; compose up -d --wait --wait-timeout "$COMPOSE_TIMEOUT" ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
