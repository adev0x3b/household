# Security

## Reporting a vulnerability

Please report it privately, through GitHub's **Report a vulnerability** on this repository's Security tab, rather than in an issue. Say what you found, how to reach it, and what it lets someone do. You'll get an answer within a few days. The fix will credit you, unless you'd rather it didn't.

The live demo (`/demo`) is open to everyone, and its data is rebuilt every night. Testing against it is welcome, as long as it doesn't degrade the service for others: no load tests, no flooding of the rate-limited endpoints. Don't test against other households' data.

## How the app protects what it keeps

These are the decisions a report is likely to touch, and where each one lives.

- **One household never sees another's data.** Every record belongs to a profile, every profile to a household. Records are reached only through `accessible_by` scopes and Pundit policies. An action that doesn't ask Pundit raises instead of answering. The few exemptions, the public pages for instance, each declare why, and a test lists them. Sharing and pickers are limited to housemates (`WithinHousehold`). Two test suites hold this:
  - `test/policies/policy_matrix_test.rb`: each kind of record × owner, sharee, housemate, someone of another household, the admin × each action;
  - `test/integration/tenancy_test.rb`: every route that names a record, requested by someone of another household, must answer 403 or 404. It is generated from the routes, so a new route is covered when it is drawn.
- **Accounts.**
  - Invitation only, with no sign-up.
  - Passwords of at least 12 characters, with no other rules (NIST SP 800-63B).
  - Ten wrong passwords lock an account for 15 minutes. So anyone who knows a username can keep that account locked, by trying again every quarter of an hour. That is the accepted cost of the lock.
  - Refusals never say whether an account exists. The one exception is deliberate: an email address is unique across the installation, so inviting an address that another household already uses is refused as taken. A member who may invite can learn whether an address has an account here, and nothing more.
  - Sessions end after twelve idle hours unless "Remember me" is ticked.
  - There is no "forgot your password" email to intercept: a new password comes from a link a household's owner or the admin makes, shown once. The person is notified, with a push, whenever one is made for them.
  - The admin types their password again before making someone such a link, removing someone, saving the app's or the assistant's settings, or changing production, at most once every 15 minutes. A wrong one counts toward the lock.
- **Rate limits** on signing in, accepting an invitation, setting a password from a link, the demo, the setup page, messages and reactions, the assistant, links, uploads, book lookups and public file links. Making invitations is bounded by each household's limits instead.
- **The browser.**
  - A Content Security Policy with nonces: scripts, styles, fonts and connections from the app alone, and no framing (`config/initializers/content_security_policy.rb`). A nonce lasts the session rather than one page, because Turbo keeps the first page's policy for every visit after it.
  - A Permissions Policy that allows the camera and autoplay (the barcode scanner's muted stream) and screen wake lock (uploads) to the app's own pages, and turns the rest off.
  - All text rendered as text: a lint rule forbids `html_safe`/`raw` in views and controllers.
  - A GET never changes data.
  - Cookies are sent only to the app's own path, so an installation served under a path of a shared domain (`MOUNT_PATH`) never hands its session to the domain's other apps.
- **Files.**
  - Uploaded files live outside the web root and are downloaded only through controllers that authorize each request.
  - Active Storage's own routes, whose signed URLs never expire, are turned off.
  - A public file link keeps only its token's SHA-256. It can expire, count down its downloads, and take a password, and too many wrong passwords revoke it.
  - Message pictures are re-encoded without their metadata, and one that can't be re-encoded is refused.
- **Logs.** A request is logged with the ids of the records it was about, and every other parameter, a message's text, a note, a lab value, a search, is written `[FILTERED]` (`config/initializers/filter_parameter_logging.rb`). A new field is kept out without anyone having to list it. The assistant's log lines name the tool and how it ended; what it read and wrote is logged only at debug level, which production doesn't use. A public file link's token, which is part of its path, is written `[FILTERED]` too (`config/initializers/request_logging.rb`). The reverse proxy in front, kamal-proxy, does log whole paths and query strings, so its log stays on the machine.
- **Secrets.** API keys saved in the app are encrypted in the database (Active Record encryption), and none is ever rendered back. The deploy secrets live in one GitHub environment per destination, which only `main` may use, and only the deploy job reads them, on GitHub's runner or on the household's own, a machine apart from the one that serves the app.
- **CI and pull requests.** A pull request from a fork runs only once a maintainer has approved the run, on GitHub's runners. If the repository ever uses a runner of its own, that runner refuses any job that isn't the repository's own code, with a check on its machine that no workflow file can change.
- **The assistant** acts only as the person chatting, through the same policies. Every change it makes shows on a card: a risky one (a deletion, a share) waits there for the person to apply it, and the others can be undone from it. Text read from a photo is handed to the model as a document, never as instructions.

## Checks on every change

CI runs Brakeman, `bundler-audit`, the importmap audit, `npm audit` for critical advisories in the lint and test tools, gitleaks over the history, the linters (RuboCop with the app's own cops, ESLint, Stylelint, ShellCheck), and the tests: the two suites above, accessibility (axe) in the browser, and N+1 detection on every request.
