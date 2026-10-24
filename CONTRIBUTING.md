# Working on Household

## Running it

You need:
- **Ruby** as in `.ruby-version`.
- **PostgreSQL 16.** The app's role must be allowed to create extensions (`pg_trgm`, `unaccent`) and, for the tests, to disable foreign-key triggers when fixtures load, which a superuser role is.
- **libvips.** Message pictures and the assistant's photos are processed with it.
- **Tesseract** (with the English and Italian data) is optional: without it, the tests that read a lab report from a photo skip.
- **Node 20.19 or later and ShellCheck**, for the linters and the JavaScript unit tests `bin/ci` runs. The app itself runs without them.

```sh
cp .env.example .env     # the database role, and the assistant's model if you have one
bin/setup                # gems, databases, then bin/dev on http://localhost:3000
```

Without a PostgreSQL of your own, Docker can run one. Give the role a password in `.env` (`HOUSEHOLD_DATABASE_PASSWORD`) and uncomment `PGHOST=localhost` there, then start it before `bin/setup`:

```sh
docker compose -f compose.dev.yml up -d
```

It answers on 127.0.0.1:5432 (`PGPORT` in `.env` moves it, if something else already listens there), and keeps its data until `docker compose -f compose.dev.yml down --volumes`.

On an empty database the first page is the setup page, which makes the first household and its admin. `bin/rails demo:seed` builds the demo household instead: six months of life for three people, ending today. Sign in as `alex.demo` with the demo password, `demo-household` unless `DEMO_PASSWORD` says otherwise.

The assistant answers once a model is configured. That is Ollama by default (`OLLAMA_BASE_URL`, `OLLAMA_MODEL`), or Anthropic or OpenAI with a key, set on `/assistant/settings`. Everything else works without it.

## Checking a change

```sh
bin/ci                   # everything CI runs: lint, Brakeman, audits, gitleaks, the whole suite
npm run format           # format the JavaScript and stylesheets with Prettier
npm test                 # the JavaScript unit tests
bin/rails test           # the unit and request tests
bin/rails test:system    # the browser tests (headless Chrome; Selenium Manager fetches one if needed)
```

The whole suite, run under `CI` as `bin/ci` does, also:
- fails below the coverage floor (`.simplecov`);
- fails when an action a route draws is requested by no test;
- fails on an N+1 query in any request (Prosopite);
- fails when the docs or a code comment name a class, constant or method the app no longer has (`test/lib/doc_names_test.rb`);
- runs axe on every page a system test visits, and opens every form a route draws.

## Conventions

The ones a change most often meets. The shape of each domain, and the reasons for it, are in `docs/architecture/`. How code is written, from what a comment is for to how objects are shaped, is in [STYLE.md](STYLE.md); read it before a first change.

- **Views are Phlex** components (`app/components/`) and views (`app/views/`). There are no inline event handlers: behaviour lives in Stimulus controllers.
- **Every word on screen is `t()`**, in both `config/locales/en.yml` and `it.yml`. A test fails on a missing key or an unused one.
- **Authorization:** every action asks Pundit or says why it doesn't. A new kind of record gets a row in the policy matrix test.
- **Services** are a verb with `.call` (`Links::Decline.call(link, by:)`). One that can fail returns a `ServiceResult`.
- **A migration must suit the version still serving** while it runs (strong_migrations). Remove a column in two deploys: ignore it first, drop it in the next.
- **Time is the viewer's:** `Date.current` and `Time.current`, never `Date.today` or `Time.now`.
- **RuboCop is authoritative**, including the app's own cops in `lib/rubocop/cop/household/`: no `send` into another object's private methods, no `html_safe`, a 303 after a write, ARIA states written as words. `bin/rubocop -a` fixes what it can. An exception to a cop goes in `.rubocop.yml` with the reason beside it.

## Commits and pull requests

A commit says what changed for the person using the app, or for the next developer, and why. It is written as a sentence in the imperative ("Open the new recipe form for its cook"), with the reason in the body. A bug fix comes with the test that failed before it. A pull request describes what it changes and what it was checked with; its template asks for both.

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md). What you contribute is licensed under the project's [MIT license](LICENSE), as the rest of the code is.

Before a large change, open an issue to agree on it first: the design rules in [STYLE.md](STYLE.md) often change the shape a change takes. A security problem is never an issue: [SECURITY.md](SECURITY.md) says how to report it privately.

## What happens to your pull request

1. **The checks wait for a maintainer** to approve their run, the first time and each time you push. They run on GitHub's runners as two jobs: `checks` (RuboCop, the linters, Brakeman, the audits, gitleaks) and `test` (the whole suite, the browser tests and the migration check). Nothing in them needs a secret, so they run the same on a fork.
2. **A maintainer reviews it.** A change under `.github/`, `bin/`, `.kamal/` or `config/deploy*` is read with extra care, since those decide what runs with the deploy keys.
3. **Once merged, `main` checks it again** before building the image, since your pull request's run used your branch's copy of the workflows. Then the image goes to staging and the demo by itself.
4. **Production follows when a maintainer promotes it.** Each promotion that brings something new is a release, tagged with a calendar version (`v2026.11.1`), and its notes list the pull requests it ships. The newest release says whether yours is live.

A migration must suit the version still serving while it runs: strong_migrations refuses what it couldn't survive. One that only works with the app stopped is written in `safety_assured` without a `# zero-downtime:` line, and its pull request gets a warning saying so; it then ships in a release with a minute of downtime. [Delivery](docs/architecture/delivery.md#a-deploy-without-a-gap) has the details.
