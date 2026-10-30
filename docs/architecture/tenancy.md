# Tenancy: households

[Documentation](../README.md) › [Architecture](README.md)

Each customer is a **household**, and nothing crosses from one household to another.

## The model

- **A `Household`** has a name, a currency (EUR by default) and usually an **owner**, its first member (the demo's has none).
- **A `Profile`** is one person, and belongs to exactly one household. It is Devise's model, signing in by username or email.
- **Records belong to profiles, not to households.** An event has a `profile_id`, a book has a `profile_id`, and there is no `household_id` on them. A household's data is its members' data.
- **Units are the exception:** a household's vocabulary ("mg/dL", "pcs"), shared by its members (`units.household_id`).

Records are only ever reached through `accessible_by(profile)` scopes and Pundit policies. What a profile can reach is:
- what it owns;
- what a housemate shared with it;
- what a linked housemate lets it see.

All three stay inside the household.

Each way in is looked up on its own, through an index that starts from the profile (the record's owner, the share's sharee, the grant's grantee), and the scope reads only the rows those lookups name. So what a person's page reads grows with their household, never with how many households the installation serves.

## How the boundary is held

- **`WithinHousehold`.** A share, a payment's other side, a unit on a record: each one that names another profile or a household's row validates that it is of the same household (`validates_within_household`, error `outside_household`).
- **Pickers.** Every picker that offers people lists `profile.housemates`, the joined members of the same household. Code never offers `Profile.all`.
- **Authorization on every action.** An action that doesn't ask Pundit raises. The few exemptions (public pages, one's own settings) each declare why, and a test lists them.
- **Tests.**
  - The policy matrix: each kind of record × owner, sharee, housemate, someone of another household, the admin × each action.
  - The tenancy test: every route that names a record, requested by someone of another household, answers 404, as if the record didn't exist. A 403 would tell them it does, since ids are sequential. It is generated from the routes, so a new route is held to it the day it is drawn. An id sent in a form's body instead (a restock's therapy, the person something is shared with, the calendar a new series goes on, a payment's counterparty, a meal's recipe, a dose's supply) is held to the same answer by a list of those forms in the same test: each refuses, names nothing of the other household's and keeps nothing against it.

## Joining

There is no sign-up. A household grows by invitation:

1. **A member invites** someone by email from the household page (`Households::Invite`).
2. **The link to accept is shown once**, to copy and hand over. The database keeps only its digest, and no email is sent. An invitation lasts two weeks, and its inviter can make a new link (`Households::RenewInvitation`) or take it back (`Households::CancelInvitation`).
3. **The invitee follows the link** and chooses a username and password. In the same transaction they join (`Profiles::Join`): they get the standard analytes and a place in the household's conversation, with its history. The setup page's first account and the demo's people join the same way.

Limits are the installation's (`Platform.household_size`, `Platform.invitations_per_member`), set by the admin in the first setup and on `/admin/settings`, and none until set:
- the people a household may hold, pending invitations included;
- the invitations each member may send into their own household, with a cancelled one given back.

`Household#places_left` and `Household#invites_left_for` read them, `nil` meaning no limit. Lowering a limit below what a household has removes nobody: it invites no one until there is room again.

A limit is checked and the invitation saved under the household's row lock, so two requests at once can't both take the last place.

A forgotten password works the same way. The household's owner or the admin makes a link to set a new one, shown once (`Profiles::PasswordLink`), and the person is told at once, by name of who made it. Whoever invited the person does not: setting someone's password is becoming them, and having invited them is no reason to hold that for good. There is no "forgot your password" email to intercept.

## The owner, and leaving

The owner can remove any other member. Removing someone goes through `Profiles::Destroy`:
- **What they kept is deleted:** their series and days, files, messages, books, pantry, links, notifications.
- **What others kept about them is unlinked:** a payment loses its other side, a series shared with them is no longer shared, a housemate's visit or purchase filed in one of their therapies stays the housemate's in no therapy, and a cost about one of their purchases is about nothing.
- **The order:** rows are deleted straight from the database in the order the foreign keys allow, with no callbacks, because nothing needs giving back to a stock that is going away too.
- **Files last:** a message's pictures and a file's bytes are deleted once the transaction commits, so a removal that fails halfway leaves every file of what is still there.

`Profile` declares no `dependent:` associations. A plain `profile.destroy` fails on a foreign key rather than half-remove a person. `Households::Destroy` removes a whole household the same way.

**The deletion test** reads what a household owns from the schema: every row that reaches the household through a reference that can't be empty. Each such table must hold a row of the test household, none may be left after, and the other household's rows must be unchanged. A new table that points at a profile is part of the test the day it is created.

A second test removes one person while the housemates stay. It reads what that person owns from the schema the same way. All of it must go, and every other row of the household must stay, except their direct conversations and what they did under a housemate's bell, which go with them.

## The admin

The person who runs the app is a profile with `role: admin`, in a household of their own. They:
- create households (a name and the first member's invitation, saved together or not at all);
- keep the app's settings (API keys, the deploy token, encrypted in the database), saved after typing their password again;
- read errors and jobs;
- run the delivery console.

Being the admin gives no access to any household's records, with one exception: they can make anyone a link to set a password, and remove anyone. Both wait for the admin to type their password again, at most once every 15 minutes, as a deploy does (`Admin::Sudo`).

On an empty database the first visitor is sent to the **setup page**, which sets up the whole copy at once and signs its admin in. The page disappears once anyone exists.

The first setup asks everything a copy needs, in one form shown a step at a time: the admin's account and language, the household's name and currency, what the installation allows, the assistant's provider and model (skipped when the assistant is off; a Test press tries the key and lists the provider's models before anything is saved), the Bookshelf's key and budget, the people to invite, then a review of every answer. Each step is an ActiveModel form object, listed in `Setup::STEPS`, with its view in `Views::Setup::Steps::BY_STEP`; the allowances, the assistant and the Bookshelf are the same section objects `/admin/settings` and `/assistant/settings` edit. `Setup::Complete` checks every step and saves them in one transaction, or nothing. A refused form comes back at the first step with something to fix. The invitation links are shown on the page that answers the form, the only time they can be read. The time zone isn't asked: the browser tells it, as on every sign-in.

Before anything else, the page asks for the copy's **setup code**: sixteen characters, made on the machine and printed to whoever runs it, so a stranger who reaches the address first can't make themselves the admin. The database keeps only the code's digest (`SetupCode`, on `Platform::Setting`). A right code opens the setup to that browser until the first account exists, which spends it; a wrong one is refused with the same words, five tries a minute from one address. `bin/rails setup:code` makes a new code, replacing any before it, and refuses once anyone exists. Without a code the page offers no form, only that command. A development server, which nothing installs, makes its own code the first time the page is opened and prints it in its output (`config.x.makes_its_own_setup_code`).

## Installation settings

What a copy of the app lets its people do is set for the whole installation and read through `Platform`. Everything is on and unlimited unless said otherwise:
- the assistant: off, its tab is gone and its pages are a 404; the admin's settings page stays;
- Files: off, nobody uploads a file or makes a public link; what is there is seen and downloaded;
- pictures in messages and photos to the assistant;
- members inviting people (the admin always can);
- push notifications: off, no device subscribes, even with VAPID keys;
- looking for a newer release once a day;
- what a household may ask the assistant, and Open Library, in a day, and what it may keep in Files (50 GB unless said otherwise).

The admin sets them in the browser, on the "What this installation allows" and "Bookshelf" cards of `/admin/settings`, and they are saved on `Platform::Setting`. Each card is a section object (`Installation::Allowances`, `Installation::Books`), saved together by `Installation::Save`, so the first setup can ask the same sections. What is saved there decides. **The environment only starts a limit**: a limit it names (`ASSISTANT=off`, `FILES_QUOTA=512MB`, …; the names are `Platform::LIMITS`) reads the environment's value until the settings row exists, and the row is made holding it (`Platform::Setting.first_or_start`), so the first setup opens on it and the admin changes it from there. An empty variable gives nothing, since Compose and Kamal pass one nobody set as an empty string. `OPEN_ACCOUNTS`, the usernames anyone may enter as without a password, comes from the environment alone.

The pipeline's destinations name every limit in their environment, which is where each begins: each destination's defaults are in its Kamal file (`config/deploy.<destination>.yml`: the demo's turn off what a public playground mustn't do), and its own values come from its environment under the same names — a file on the machine for deploys by hand, its GitHub environment for the pipeline.

A policy or a controller asks `Platform` (`Platform.uploads?`, `Platform.pictures?`, …); no household is special in the code.

## The demo

The public demo is an **installation of its own**, with its own database, running the same code as every other copy. Its data is a household with three members and six months of life ending today:
- **Built by `Demo::Seeder`**, one day at a time, through the app's own code. It is also the sample data of every development database (`db/seeds.rb`). The household has no owner, so no visitor can remove the others.
- **Rebuilt every night** on the demo installation alone (`Demo::ResetJob`, `config/recurring.yml`).
- **Entered without a password.** The demo installation declares its three accounts open (`OPEN_ACCOUNTS`): its sign-in page offers them as buttons, and entering is a POST (`DemosController`). A GET signs nobody in, because Turbo prefetches links and any site could link a browser in. On the way in the account is unlocked, so a stranger's wrong passwords never keep the next visitor out. An admin is never an open account, even when `OPEN_ACCOUNTS` names one: entering as them without a password would hand anyone the installation. Any other copy's `/demo` sends the visitor to the demo installation (`DEMO_HOST`).
- **Limited by its settings**, not by code: uploads, pictures, invitations and push are off, the assistant and the bookshelf's lookups have a day's budget per household (the lookups' is `Books::LookupAllowance`). A feature that costs money or reaches outside the app gets a setting of its own, which the demo installation turns off.

## Rate limits

Sign-in, accepting an invitation, setting a password from a link, entering an open account, the setup page, messages and reactions, the assistant, asking a housemate to link calendars, uploads, book lookups and public links' pages are all rate-limited (`rate_limit`, counted in Solid Cache; what one person does is counted per person, `rate_limit_per_person`, since a household shares an address). An answer over the limit is a toast and a 429 for Turbo, a 429 for JSON, and an alert and a redirect for a page.

---

Using it: [People](../guide/people.md)
