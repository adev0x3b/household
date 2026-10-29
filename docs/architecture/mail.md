# Mail

[Documentation](../README.md) › [Architecture](README.md)

Household mails people for three reasons: the reminders someone asked to have by email too, a link to set a new password for someone who forgot theirs, and the notices that keep an account safe (the password changed, the address changed or about to, the link that confirms an address). It mails nothing else, and nothing to an address its owner hasn't confirmed but the link that confirms it. An address is one mailbox: one that lists several, which a mail would reach every one of, is refused where it is typed and again where a mail is made. Invitations are still handed over by hand ([Tenancy](tenancy.md)).

## Where it goes out

All mail leaves through one SMTP relay, which the admin sets on the Mail card of `/admin/settings` and in the first setup: its server, port and encryption (STARTTLS, TLS from the start, or none for a catcher on the same machine), a login, and the sender's address (`Emails::RelaySettings`). A field left empty follows the environment's (`SMTP_HOST`, `SMTP_PORT`, `SMTP_TLS`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM`), but a relay saved on the card never borrows the environment's login. The password is encrypted like the other keys and never shown again. A login with no encryption is refused rather than sent in the clear.

Mail is a switch like the others (`Platform.outgoing_mail?`): on unless the admin turns it off. Staging, dev and the demo start with it off, so a copy of real addresses never mails anyone from there.

Only the job worker talks to the relay, with a deadline of 15 seconds for each answer, so a slow relay never holds a page.

## The outbox

Every mail is first a row of the outbox (`OutgoingEmail`), one per mail to one person, queued by `Emails::Enqueue`:
- its kind, from when it may go, and until when it is still worth sending;
- ids, dates and times, never words: the words are made as it goes out, in the person's language and time zone. An address only for a notice that must reach the one the person had when it was queued (an address another took over from, the one confirmed when the password changed), cleared once the row ends;
- no link: a token is made as its mail goes out, so the outbox never holds one.

`Emails::DrainJob` sends what is due, every minute and at once after account mail is queued, one drain at a time (`Emails::Drain`). A drain claims a batch under its household's row lock before it makes the message, so no two drains send one row, and every row ends one way: sent, failed or dropped.

Each kind of mail is a class in `Emails::Kinds.all`, which says how long a row of it is worth sending, which rows go out together, and how its message is made. The list's order is the order mail goes when the budget is short: a link someone waits for at the door first, the reminders last. A kind whose message is no longer wanted when its turn comes (an address no longer confirmed, a reminder done meanwhile) drops its rows rather than send them.

## Budgets

Every budget counts messages taken to go in the rolling hour or day, the refused ones too, so a relay that refuses everything fails no more mail in an hour than the budget.

- **The installation**: `Platform.mails_per_hour` and `Platform.mails_per_day`, every household together (`Emails::RelayAllowance`). Mail that isn't about an account (reminders, the admin's tests) leaves the last of each hour and the last five of each day to the mail that is, so a busy morning of reminders never keeps a link to set a password from going out.
- **A household**: its reminders in a day (`Platform.reminder_mails_per_day`, `Emails::ReminderAllowance`), and its account mail, at most half of each of the installation's budgets (`Emails::AccountMailAllowance`), so one household never spends another's. A household over its budget waits a quarter of an hour, then is asked again.
- **A person**: three links to confirm an address a day (`Emails::ConfirmationAllowance`), and three links to set a password a day, with two an hour and ten a day for the whole installation (`Emails::PasswordLinkAllowance`). Notices of a password changed several times while they waited go out as one.

## What the relay answers

`Emails::Relay` reads every answer as one of three things, and the drain answers each its own way:

- **It isn't answering**, or asks to try later: the mail waits two minutes, then four, then eight, up to six hours, eight tries in all, and nothing else is tried until the next round.
- **It refuses this copy's settings** (the login, STARTTLS, TLS, the certificate): the mail goes back as it was, all mail pauses for 15 minutes (`Emails::RelayPause`), and the admin is told on the bell, once an hour at most. The admin's page of mail says what to fix, and a test mail from it ends the pause.
- **It refuses one message**: that mail fails, keeping the relay's reply with its addresses masked, and the rest goes on.

A relay refuses a sender it won't send for and a message it won't take with the same codes. Such a refusal is told apart by the mail around it: once other mail has gone out since, it was the message, which fails. Until then the mail is held behind all the other mail due, and only a second address refused that way in the same round, or the held mail refused again with nothing gone out in between, pauses the relay as above. One bad address never stops everyone's mail.

## Reminders by email

A reminder (`EventReminder`) can be **also by email**. The form offers it while mail goes out and the person's address is confirmed, never to an open account, whose address is nobody's who uses it, and not while the admin allows households no reminder mail (`Emails.for_reminders`).

`Reminders::DispatchJob` queues a row for each reminder by email that falls due, and the next drain sends each person's together, at most 25 to a mail. A reminder goes out only if, when its turn comes, it still asks for email, its person may still read the series, and the day is still to do and not yet due (`Reminders::StillDue`). Its row expires when its thing is due.

A reminder mail names a task, a meal or a payment, with its time. It never names a medication, a lab test or result, or an appointment, only their kind: a mail is read on a lock screen, and passes through mail servers the household doesn't run. A payment for one of those, or for a medical supply, is only "your payment", since the app titles a fee or a price after what it pays for (`Event.named_in_mail?`). It stays so once that thing is deleted and the payment kept, or the payment is moved to another, as its title may still be the one made after it (`Transaction::Details#named_in_mail`). A payment kept from before mail came, whose thing was deleted then, can't say what it paid for: it is kept out when it is filed under healthcare, as every such fee is but a visit's that wasn't medical. Its subject is the same for every kind.

Its foot holds a link that stops every reminder by email, for whoever holds it and without signing in (`EmailUnsubscriptionsController`, `Reminders::StopEmail`), and the mail carries it as `List-Unsubscribe` with one-click unsubscribe, so a mail client offers it too. The link works for 90 days, and stops working once the address is confirmed again. Mail sent by the app says it is automatic (`Auto-Submitted`), so vacation replies leave it alone.

## Accounts by mail

The Account page (`/account`) is each person's own: their address and their password.
- **Confirming an address** mails it a link that works for a day (`Profiles::SendEmailConfirmation`, `Profiles::ConfirmEmail`). Opening the link, signed in, shows a page with a button, since mail scanners open links on their own; only the press confirms, and it asks for the password (`Accounts::EmailConfirmation`). The link shows the mailbox is the person's and the password that the session is, so an address someone else typed, as an inviter does, becomes where a link to set a password goes only by the person's own hand. A link made for a mail that then couldn't go out stops working, so the page offers to mail one again rather than say one went.
- **Changing the address** asks for the password. The new address waits for its link, and the confirmed one is told first, so a stolen session can't move the account quietly (`Accounts::EmailChange`). Where no mail goes out, the new address takes over at once, unconfirmed.
- **Changing the password** asks for the old one, signs the person out everywhere else, and tells the address confirmed then, even if another takes over before the mail goes (`Accounts::PasswordChange`).

**"Forgot your password?"**, under the sign-in form while mail goes out, asks for a username or an address. The answer is the same, after the same work, whatever was typed: the page queues a job with the id it found, or none, and the job decides (`Profiles::PasswordLinkRequestJob`, `Profiles::RequestPasswordLink`). A link goes only to a confirmed address of someone who has joined, within the limits above, and one at a time: none is mailed while another is on its way or still works. It works for 30 minutes and once. The newest link wins: one handed over or printed on the server while the mail waited means the mail makes none, and a link made for a mail that then couldn't go out stops working, without touching one made since. The admin never gets one by mail: their way back is the server (`bin/rails admin:password_link USERNAME=…`, or `household password-link` on a copy of one's own), and the household's owner and the admin can still make anyone a link to hand over.

A page opened from a link carries its token in the address, so it tells no other site where it came from (`Referrer-Policy: same-origin`).

## The admin's page of mail

`/admin/emails` (`Emails::Overview`) says whether mail goes out, and what stops it otherwise; the relay and the sender; what went out against the budgets in the last hour and day; what waits; and what couldn't go out in the last 30 days, whose it was, why, and what the relay answered. It shows no mail's words, since the outbox keeps none. Sent rows are swept after a week, the rest after 30 days (`Emails::SweepJob`).

Logs hold ids. What the relay answered is kept with every address in it masked (`Emails.without_addresses`), and any other error keeps only its class on the row, its message going to the error report.

---

Using it: [The calendar](../guide/calendar.md#reminders), [People](../guide/people.md), [Admin](../guide/admin.md)
