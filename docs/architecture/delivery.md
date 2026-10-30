# Delivery

[Documentation](../README.md) › [Architecture](README.md)

The deploy host runs four copies of the app, behind one proxy:
- **production**, at the public address;
- **staging**, behind an access gate;
- **demo**, the public demo, at its own address with nothing in front;
- **dev**, behind an access gate.

GitHub Actions builds each commit once into an image, and Kamal puts that image on the host. The deploy workflows do nothing in a repository without a `DEPLOY_HOST`.

## A change travels dev → main → staging → production

```
a branch ──preview──► dev            (built from the branch, on dev's disposable data, or fresh)
    │
pull request: CI ──merge──► main ──CI──► image ghcr.io/<owner>/household:<sha>, built once
                                              │
                                              ├──automatically──► staging ──then──► demo
                                              └──a promotion press──► production (the image staging runs)
```

- **CI** runs on every pull request and push: RuboCop with the app's own cops, ESLint, Stylelint and Prettier for the front end, ShellCheck, Brakeman, `bundler-audit`, the importmap audit, `npm audit` (critical advisories only), gitleaks, and the whole suite, browser tests included.
  - A pull request's new migrations are also run on the schema they merge into, which is what a deploy will do. strong_migrations refuses an operation the version still serving couldn't survive.
  - Every night, `main`'s tests run again with the clock a year ahead.
- **The image** is built once, for a commit on `main`, and tagged with its sha. **The host never builds:** staging and production run that exact image, and a rollback is the image of an earlier commit.
- **Staging** follows `main` by itself, and **the demo** takes the same version right after staging has it. **Production** moves only when promoted.
- **A promotion is also a release** when it puts a newer version on production: a calendar version, the image tagged with it, and a GitHub Release with the files a self-hosted copy installs from. Self-hosted copies follow releases, never `main`.
- **Only a commit on `main`** may reach staging, the demo or production. A branch's image only ever reaches dev.
- **The demo's data is disposable** and starts over every night, so it takes deploys and restarts and nothing else.
- **Dev can be stopped** while nothing is previewed. Its data is kept, and the next preview starts it again.
- **Each destination's GitHub environment names its machine**, so the four can share one host or spread over several, and one moves to another machine with `bin/provision move`, run there. Each container's memory cap is a setting of its destination.

## Two ways to run a copy

The pipeline above runs the project's own copies. A self-hosted copy runs without it, from a release ([self-hosting](../self-hosting.md)): `install.sh` puts the release's `compose.yml` in a directory with the installation's answers, one Compose project with the database, the web server, the jobs and three volumes, and the image production runs pinned by its digest. The two share the image, the entrypoint that makes the secrets and migrates, and the names of every setting. What differs is what the machine does: the pipeline's host swaps versions with no gap; a self-hosted copy takes a few seconds' pause on each update, with no migration ever running beside the version before it.

## A deploy without a gap

Kamal starts the new version's web container, which runs its migrations. Once its health check (`/up`) answers through the proxy, every new request goes to it, and the old container finishes what it was answering. A version that never becomes healthy is stopped, and the old one carries on.

So **a migration must suit the version still serving**, and a rollback runs the previous version on the migrated database:

1. Add the column, table or index in one deploy.
2. Start using it.
3. Stop using the old one, then remove it in a later deploy. A column being removed goes into `self.ignored_columns` one deploy before; its `remove_column` then sits in `safety_assured` with a `# zero-downtime:` line.

strong_migrations (`config/initializers/strong_migrations.rb`) refuses removing or renaming a column or table, changing a type, and blocking index or constraint operations, in development, CI and production's boot. Migrations wait at most 10 seconds for a lock and must finish within the 180 seconds the new version has to answer, so a new column is filled from a job after the deploy.

strong_migrations wants `safety_assured` around whatever it can't vouch for, routine steps included, so a migration that uses it says on a line of its own whether it runs beside the previous version:

```ruby
# zero-downtime: Book has ignored isbn10 since the previous deploy
safety_assured { remove_column :books, :isbn10 }
```

Without that line, the migration needs the app stopped. Forgetting it holds production; it can't break it.

A migration that can't be split is held: production waits, and the pull request says so. Staging first rehearses it on a copy of production's data, behind a maintenance page, and records how long production would be down. Then one press releases it to production the same way, and it puts itself back if it fails. The demo, whose data starts over every night, needs no rehearsal and no press: it takes such a version behind its own maintenance page.

Before every production deploy, a hook dumps the database.

## Releases

A release is a version someone promoted to production and production then ran: the promotion starts `release.yml`, which only the repository's owner may publish.

1. **`prepare`**, read-only, on `main`'s code: `bin/release` decides whether the commit is a new release and which version, then writes the notes and the files. A version older than the last release, or one released already, makes none.
2. **`arm64`**: the same commit built for arm64, pushed as `<version>-arm64`.
3. **`publish`**: production's own amd64 image gets the tag `<version>-amd64`, unchanged, and `<version>` and `stable` become an index of it and the arm64 image. GitHub signs a provenance attestation for the image and each file (`gh attestation verify <file> --repo <owner>/household`), and the GitHub Release is made, marked latest.

**Versions** are `v<year>.<month>.<n>`, the month unpadded and `n` counting from 1 in each month, in UTC: `v2026.11.1`, `v2026.11.2`, `v2026.12.1`. The version without its `v` names the image: `ghcr.io/<owner>/household:2026.11.1`.

| File | What it is |
|---|---|
| the notes | The pull requests merged since the release before, oldest first. An update that stops the app while the database changes says so first, with how long production was behind its maintenance page. |
| `release.json` | The release, for scripts (below). |
| `compose.yml` | The commit's `compose.yml`, with the image pinned by tag and digest. |
| `install.sh` | The commit's installer, as it is. |
| `SHA256SUMS` | The checksums of the other files, as `sha256sum -c` reads them. |

`release.json` is the contract the installer, the `household` command and the app's release check read:

```json
{
  "version": "2026.11.1",
  "tag": "v2026.11.1",
  "commit": "<the full sha>",
  "image": "ghcr.io/<owner>/household:2026.11.1@sha256:<digest>",
  "previous": "2026.10.3",
  "stopped_migrations": [ "db/migrate/<…>.rb" ],
  "downtime_seconds": 41
}
```

`previous` is null for the first release. `stopped_migrations` lists the migrations since the release before that need the app stopped, and `downtime_seconds` is how long production was behind its page for such a release, null otherwise. Every file is at `https://github.com/<owner>/household/releases/download/<tag>/<file>`, and the newest release's at `…/releases/latest/download/<file>`.

A dry run (Actions → Release → Run workflow, with a commit) prepares the same notes and files and keeps them as the run's artifact for 14 days; it tags and publishes nothing.

## The delivery console

`/admin/deployment` is the deploy console, where the admin follows the delivery of the app. From it they preview a branch on dev, deploy `main` to staging, promote a release to production, or roll back to an earlier one.

It has two parts:
- **This copy** shows what the running app knows about itself: its version, its environment, when it booted, and whether the database and the job worker answer. A self-hosted copy also checks once a day for a newer release and tells the admins when it finds one.
- **The pipeline** shows dev, staging, the demo and production. From it the admin freezes automatic deploys, deploys, promotes and rolls back, through GitHub's API with a fine-grained GitHub token. A self-hosted copy has no pipeline.

## Errors and jobs

What the app rescues and goes on from is reported through `Rails.error`. Solid Errors keeps it, in its own database, and the admin reads it on `/admin/errors`. Background jobs are read on `/admin/jobs` (Mission Control). The live demo is rebuilt every night by a recurring job.

---

Running a copy: [Self-hosting](../self-hosting.md)
