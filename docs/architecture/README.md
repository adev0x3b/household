# Architecture

[Documentation](../README.md)

Household is one Rails 8.1 application: pages rendered on the server, made live with Hotwire, on PostgreSQL. There is no API or SPA: the browser receives HTML, and Turbo Streams update the parts of it that change. This page is the map. Each domain has its own page.

| Page | What it covers |
|---|---|
| [Tenancy](tenancy.md) | Households, profiles, invitations, the admin, the public demo |
| [The calendar](calendar.md) | Series and their days: the model everything on the calendar shares |
| [Sharing and links](sharing-and-links.md) | Sharing a thing with a housemate; two housemates who see each other's calendars |
| [Files](files.md) | Big files kept on the server: chunked uploads, downloads, public links |
| [Messages](messages.md) | Conversations between housemates, live |
| [The assistant](assistant.md) | The chat that files things for you: tools, change sets, evals, the dictionaries |
| [Dashboards](dashboards.md) | Home and the sections' statistics |
| [Front end](front-end.md) | Phlex, Turbo, Stimulus, the modal and form, the style system |
| [Delivery](delivery.md) | CI, the image, Kamal on one machine, the delivery console |
| [Glossary](glossary.md) | The one word for each concept, in English and Italian, and the code's name for it |

## The stack

| Layer | Choice |
|---|---|
| Framework | Rails 8.1, Ruby 3.4 |
| Database | PostgreSQL 16, with `pg_trgm` and `unaccent` for typo- and accent-tolerant matching |
| Views | [Phlex](https://www.phlex.fun) components and views (Ruby classes, no templates) |
| Front end | Turbo 8 and Stimulus through importmap: no bundler, no build step for JavaScript |
| CSS | Bulma, loaded in parts, with the app's own partials compiled by Dart Sass |
| Accounts | Devise with invitations (`devise_invitable`); the model is `Profile` |
| Authorization | Pundit |
| Background work, cache, cable | Solid Queue, Solid Cache, Solid Cable: all in PostgreSQL, each in its own database |
| Errors | `Rails.error`, kept by Solid Errors and read on the admin's pages |
| Assistant | RubyLLM, with Ollama, Anthropic or OpenAI |
| Deployment | Kamal 2, four destinations (production, the public demo, staging, dev) |

## Where code lives

Every directory has one job. A class that changes state is a service, and a class that only reads is a query. Neither lives in `app/models`, which holds records and the values they use.

| Directory | Holds | For example |
|---|---|---|
| `app/models` | Active Record models, their concerns, and the domain's value objects | `Event`, `Occurrence`, `Book::Isbn`, `Events::RecurrenceRule` |
| `app/services` | Operations that change state, one verb each, called as `.call` | `Links::Accept`, `Occurrences::Destroy`, `Uploads::Append` |
| `app/queries` | Read-only questions over many records | `Calendar::Days`, `Links::Permissions`, `Pantry::Availability` |
| `app/reports` | The dashboards' figures, one `Reports::` namespace | `Reports::Healthcare::Dashboard` |
| `app/policies` | Who may do what (Pundit) | `OccurrencePolicy`, `UploadPolicy` |
| `app/broadcasters` | Every live push, one per domain | `Conversations::Broadcaster` |
| `app/clients` | The services outside the app: one deadline, one error each, one method the tests stub | `Books::OpenLibrary`, `Delivery::Github` |
| `app/jobs` | Background work, namespaced by domain | `Messages::NotifyJob`, `Uploads::FinishJob` |
| `app/components` | Phlex: the kit every area shares, pieces that know no area | `Components::Modal`, `Components::StatusBadge` |
| `app/views` | Phlex: each area's pages, modals, cards, rows and form sections, under `app/views/<area>/` | `Views::Books::Show`, `Views::Calendar::Cards::TaskCard` |
| `app/presenters` | What turns a record or a figure into words, an address or a payload for display, and renders no HTML | `Notifications::Wording`, `Notifications::Destination`, `Occurrences::Access`, `Statistics::Format` |
| `app/javascript/controllers` | Stimulus controllers, one behaviour each | `uploader_controller.js` |
| `app/javascript/helpers`, `app/javascript/uploader` | Plain modules the controllers share, and the uploader's own objects (its queue, memory and wording), unit-tested | `interpolate.js`, `transfer.js` |
| `app/tools`, `app/agents`, `app/prompts` | The assistant's tools, its agent and its instructions | `Assistant::BookkeeperAgent` |
| `lib/demo` | The sample data: the demo household's seeder, one part per side of its life | `Demo::Talk`, `Demo::Money` |

## How a change travels

Take ticking a task done on the calendar.

1. **The card's circle** is a link to the day's completion (`/events/:event_id/days/:date/completion`), with `data-turbo-method="post"` to put it there and `"delete"` on a day already done. Turbo sends it and asks for a Turbo Stream answer. A day of a repeating series that nothing was stored about yet has the same address, so ticking it saves the day and marks it in one step.
2. **The controller** (`DayCompletionsController`, the same for every kind of series) finds the day through its series (`DayLookup`) and **authorizes** it with its policy. Every action asks Pundit or says why it doesn't, or it raises. If a linked housemate's grant says "ask", the change is held for its owner's OK instead (see [Sharing and links](sharing-and-links.md)).
3. **The model** changes through one method, `Occurrence#complete!`. It saves the day and runs its kind's hook: a medication draws its supplies from stock, a meal empties the pantry.
4. **The response** is the toast the person who ticked sees, as a Turbo Stream.
5. **Everyone who has that month open** gets the day's card redrawn, the person who ticked included. `Calendar::DayCardBroadcaster` renders it for each of them, in their language and time zone, and pushes it over Action Cable.

The same shape holds across the app:
- a controller authorizes;
- one service or model method writes;
- the response answers the person who acted;
- a broadcaster tells everyone who is looking.

## Live updates

Pages subscribe to their own streams:
- the calendar to its month;
- a conversation to its messages, for that viewer;
- the bell to the person's notifications;
- a grocery list to its items.

A broadcaster renders the same Phlex component the page uses, as each viewer would see it, and a failed push is reported, never allowed to fail the request. Pushes that do real work (a message to every participant) run from a job, so a request never waits on them.

## Background work

Solid Queue runs the jobs, with a worker of its own for the assistant's replies. One retry policy covers them all:
- a deadlock or a lost connection is retried, later each time;
- a job whose record is gone is discarded;
- a job whose work can't be done twice (the assistant's reply, a dictionary import) is marked so and fails instead.

Recurring work (reminders, the demo's nightly rebuild, sweeping abandoned uploads) is declared in `config/recurring.yml`.

## The database

Beside the models' validations, the database holds the data to rules of its own, so a write that goes around a model (a bulk update, a migration, a console) can't leave a row the app would refuse:
- every reference is a foreign key, and has an index that starts with its column, so deleting the row it points at never scans the table. Two references that must agree are one key: a day's details point at the day and its series together;
- whatever must be unique has a unique index, which the model's validation only words for the person. The index compares as the app does: a username is one person's in any case, so its index is on `lower(username)`;
- a value with a rule of its own (a positive quantity, a rating from 1 to 5, a currency's three capitals, bounds in order) has a CHECK constraint beside its validation. A list the app grows with its features, such as an enum's values, stays the model's alone, so a new value never needs a migration.

An index is there for a lookup the app makes. One whose columns another index of the same table already starts with is left out, since the longer index serves the same lookups and the shorter one would only slow every write. The tests in `test/db` hold these rules. A migration runs while the previous version still serves, so it must suit both ([Delivery](delivery.md)).

## Time, language, money

- **A day is the viewer's day**. Every request runs in its viewer's time zone. Anything made for someone else (a broadcast, a push, a reminder) is made in theirs.
- **Every word on screen** is translated, in English and Italian.
- **Money** is shown in the household's currency, and never summed across currencies.

## Tests

- **Minitest**, with fixtures, the system tests in headless Chrome, and **axe** in the browser.
- **Two suites that hold the authorization model** (`test/policies/policy_matrix_test.rb` and `test/integration/tenancy_test.rb`).
- **A suite that holds deleting** (`test/integration/deleting_what_is_referenced_test.rb`): every route that deletes a record is tried on one that each reference in the schema points at. It must refuse or delete cleanly, never answer 500, and never leave a reference to a row that is gone.
- **A suite that holds locking** (`test/integration/locks_test.rb`): every lock the code takes is shown to be waited for while another connection holds it.
- **A check that every routed action is requested by some test.**
- **N+1 detection** on every request.
- **A coverage floor.**

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for how to run them.
