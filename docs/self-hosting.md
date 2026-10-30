# Self-hosting

[Documentation](README.md)

One machine with Docker is enough. You install a **release**, a version of the app that the project's own production runs, and it lives in one directory: a Compose project with a database, the web server, the jobs and three volumes. There is no clone, no Ruby and no build.

## What you need

- **Docker Engine with the Compose plugin** on Linux, or Docker Desktop on macOS or Windows. On a Linux machine without Docker, the installer offers to install it with Docker's own script.
- **A way for people to reach it.** The installer asks, and each answer is a few lines it writes for you. For everything the app can do, a phone needs HTTPS: over plain HTTP the app works in a browser, but a phone can't install it as an app, receive push notifications or scan a barcode.
- Optionally an **Ollama** on the machine, or an Anthropic or OpenAI key, for the assistant. Everything else works without it.

## Installing

```sh
# READ THE INSTALL SCRIPT CAREFULLY AND CHECK ITS SHA
curl -fsSLO https://github.com/adev0x3b/household/releases/latest/download/install.sh
less install.sh
sh install.sh
```

Run it as yourself. Where a step needs root (installing Docker, a Docker that answers only to root, Tailscale), it asks for your password once, just before that step. It downloads the release's `compose.yml` and `release.json`, checks both against the release's `SHA256SUMS`, and installs nothing when they don't match. Then it asks three things:

1. **Where Household keeps its files** (`~/household`).
2. **How people reach it:**

| Answer | What it writes in `household.env` | Then |
|---|---|---|
| 1 Only this computer | `BIND=127.0.0.1`, `FORCE_SSL=off`, `APP_HOST=localhost` | open `http://localhost:8080` |
| 2 Devices on the home network, over plain HTTP | `BIND=0.0.0.0`, `FORCE_SSL=off`, `APP_HOST` = the name or IP asked | only that name opens it |
| 3 Tailscale | `BIND=127.0.0.1`, `APP_HOST` = this machine's tailnet name | the installer runs `tailscale serve`, so the tailnet must have HTTPS certificates on |
| 4 A Cloudflare Tunnel | `TUNNEL_TOKEN`, `COMPOSE_PROFILES=cloudflare`, `APP_HOST` = the tunnel's hostname | in Cloudflare, the hostname points at `http://web:80`; nothing is published beyond the machine |
| 5 A public address with a certificate of its own | `BIND=0.0.0.0`, `PORT=80`, `TLS_PORT=443`, `TLS_DOMAIN` = `APP_HOST` = the name | the name must point at the machine already; the certificate is fetched on the first visit |
| 6 Behind your own reverse proxy | `BIND=127.0.0.1`, `PORT` and `APP_HOST` asked | the proxy forwards to `http://127.0.0.1:<PORT>` and terminates HTTPS |

3. **Whether to back up every night** (yes): at 03:30, into the directory's `backups/`, the newest seven kept. It is a line in the crontab of whoever runs Docker on the machine.

**Ports.** The app answers on `PORT` (8080) and `TLS_PORT` (8443) of the machine, whichever way people reach it. When another program already listens on 8080, the installer says so and asks for another port, offering the next free one (`--yes` takes it). The HTTPS port, which nothing reaches unless the address is public, moves to a free one by itself. A public address needs 80 and 443 themselves, so the installer stops before writing anything when another program holds either. It asks `ss`, else `lsof`, else `netstat`, and both ports stay in `household.env` for `household config` and `household update`.

The database's password is made, never asked, and the clock the app uses before anyone signs in is the machine's. The installer pulls the image, starts the containers, waits until the app answers its health check (the first boot migrates the database, a minute or two), and ends with what to open:

```
  Open   https://home.example.com
  Code   K7QM-2XRD-9VWP-HC4T
```

**The code** is what keeps a stranger from making the first account before you do. Open the address, type the code, and the setup page takes you through everything the copy needs: [First setup](guide/first-setup.md) describes it. The code stops working once the first account exists. Lost it? `~/household/household setup-code` makes a new one, and refuses once someone has an account.

`sh install.sh --yes` takes every default and reads the answers that have none from the environment (`HOUSEHOLD_DIR`, `HOUSEHOLD_EXPOSURE` as `local`, `network`, `tailscale`, `cloudflare`, `public` or `proxy`, `HOUSEHOLD_HOST`, `HOUSEHOLD_PORT`, `TUNNEL_TOKEN`, `HOUSEHOLD_BACKUPS` as `yes` or `no`). `--version 2026.11.1` installs that release rather than the newest. Run again over an installation, it leaves it as it is.

**When the first start fails** (a port taken after all, the image not pulled, the app not healthy in time), the installer prints Docker's reason, keeps the app's log in `failed-start.log`, removes the containers and keeps `household.env` and the database volume. Run it again into the same directory and it starts from the same answers, asking again for a port another program has taken. `sh install.sh --reset` starts from the beginning instead. It uninstalls what is in the directory first, asking what goes and waiting for the directory's name typed back, as `household uninstall` does (the same `--keep-data`, `--remove-backups` and `--keep-images`), and then asks every question again. It warns first when the directory holds a working installation.

## On the machine

```
~/household/
  household        the everyday command, a copy of the installer
  compose.yml      this release's, its image pinned by version and digest
  release.json     which release this is
  household.env    the installer's answers, readable by you alone
  backups/         every night, and before every update
  previous/        the release before the last update, until a rollback uses it
```

What the app keeps is in three Docker volumes named after the directory: `household_db` (the database), `household_storage` (uploads, message pictures, the assistant's dictionaries, the certificate) and `household_secrets` (the keys the app made on its first boot: without them, what the database holds encrypted can't be read back). The containers come back after a reboot.

## The `household` command

| Command | What it does |
|---|---|
| `household update` | the newest release (`--version` for another). It says when the release's migrations stop the app and for about how long, backs up, checks the new files against `SHA256SUMS`, pulls, stops the app so a migration never runs beside the version before it, and starts the new one. If that doesn't come up healthy, it puts the old version back with the data from before the update. |
| `household rollback` | the version before the last update, with the data backed up just before it: what was written since is lost, so it asks for `rollback` typed back |
| `household backup` | the database, the secrets and the files, into `backups/<when>-<version>/` |
| `household restore <backup>` | a backup put back over what is there, after `restore` typed back |
| `household config` | how people reach it, asked again; the rest of `household.env` stays |
| `household status` | the version, the address, and what runs |
| `household logs` | the app's log, followed |
| `household stop`, `household start` | stop the app, start it again |
| `household setup-code` | a new setup code, only while nobody has an account |
| `household uninstall` | the containers removed, and what it asks about: see below |

Updates never happen by themselves. The app checks once a day whether a newer release is out, and tells the admin on the bell and on the Deployment page, with the command to run.

## Uninstalling

`household uninstall` removes the containers and the nightly backup's line in the crontab, then asks what else goes, each question answered by a flag instead when it is scripted:

| It asks about | Default | Flag |
|---|---|---|
| the data: the database, the files and the secrets, in the three volumes | goes | `--keep-data` |
| the backups in `backups/` | stay | `--remove-backups` |
| the images it pulled (the app's, Postgres, cloudflared) | go, unless something else on the machine uses them | `--keep-images` |

Losing the data or the backups waits for the directory's name typed back, which `--yes` never types. With the data kept, `household.env` stays too, because its password opens the database volume: `sh install.sh` into the same directory starts Household again with everything it held. The directory stays when anything is left in it, and goes with the last of its files otherwise. A Tailscale address keeps answering until `sudo tailscale serve reset`.

## Settings

Everything about what the app does is set in the app, by its admin: what it lets people do on the Settings page, the assistant on its own settings page. `household.env` holds only the installer's answers. A setting written there before the first setup (`UPLOADS=off`, `FILES_QUOTA=10GB`; the names are listed in the release's `compose.yml`) is where the Settings page starts, and the admin changes it there like any other. Written later, it changes nothing: the page keeps what was saved.

## Backups

A backup is a directory holding `database.dump` and `files.tar.gz` (the `storage` and `secrets` volumes), readable by you alone. Keep it as safe as the data: the secrets open what the database holds encrypted. Each one holds every file people uploaded, so a household with many files needs room for seven of them; copy them off the machine to keep them through a broken disk.
