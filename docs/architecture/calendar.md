# The calendar: series and their days

[Documentation](../README.md) › [Architecture](README.md)

Everything on the calendar is one shape: a task, an appointment of any kind, a medication, a meal, a lab result, a payment. Each is a **series** (`Event`) with **days** (`Occurrence`). A one-off is a series with one day. A daily medication taken at breakfast and dinner is a series with two doses a day, every day. This page is about that shape, because every feature that touches the calendar builds on it.

## Kinds of series

`Event` is a single-table-inheritance base: `Task`, `Appointment`, `Medication`, `Meal`, `LabTestResult`, `Transaction`. **The hierarchy is the registry**. Everything that enumerates the kinds reads `Event.types`:
- the routes;
- the day card's "+" menu;
- the linked housemates' grants;
- the deletion of a person;
- the tests that are asked of every kind.

`Event.types` maps `Event::TYPES`, the one list of the kinds, to their classes, so adding a kind is writing its class and adding its name there. The assistant keeps a list of its own (`Assistant::Resources::REGISTRY`), because it also reads records that aren't series, so a new kind gets its resource there too.

**A series** holds what every kind has: a title, notes, a place, a start time and duration, the day it starts, and how it repeats. The repeat is one RFC 5545 rule line (`rrule`, read by [ice_cube](https://github.com/ice-cube-ruby/ice_cube)), its times of the day (`event_slots`: clock times, or "with breakfast", "at bedtime"), and the days deleted from it (`event_exclusions`). `Events::Schedule` walks the rule from the first day and reads every date as its midnight in UTC, the rule's end included, so a stored line gives the same days on any machine whatever its clock's zone.

**Each kind answers its own questions on its class**: its section, its policy, what its fee is filed under, which statuses it allows, why a day of it can be skipped. **Behaviour that differs by kind is a hook on the subclass, never a `case` on the type.** For example:
- `on_occurrence_completed`: a medication draws its supplies from stock, and a meal takes its recipes' ingredients from the pantry;
- `on_occurrences_destroying`: deleting days gives back what they drew;
- `due_clock`: when a day is due, for its reminders;
- `cost_title` and `cost_counterpart`: what a day's cost is called and who it is paid to unless the cost says (a visit's provider, the place a meal was eaten).

The view side lists each kind's card and form, in `Views::Calendar::Cards::BY_KIND` and `Views::Occurrences::Forms::BY_KIND`, so a model never names a view. A test checks that every kind has both. How a kind looks is its card's to say, so its icon is the card's too (`Views::Calendar::Cards.icon_of(event)`, wherever a series is listed); an appointment's follows its kind.

## Days that exist before anything is stored about them

A daily medication has a day for every day, for as long as it repeats, and storing a row for each would mean writing the future. So **a day always exists as an object, and gets a row only once something is stored about it**. Something stored means a status, a field changed for that day alone, or a child (a lab value, what a dose really drew).

- `event.occurrence_on(date, time:)` returns the saved day, or an **unsaved** `Occurrence` (`projected?`) built from the series.
- `event.occurrences_between(from, to)` walks every day in a range, saved and unsaved alike: the rule's dates × the day's slots, minus the exclusions, plus saved days that were moved off the rule.
- `Event.preload_occurrences(events, from, to)` loads a whole month's saved days in one query, so a calendar month costs the same few queries however many series it shows.

Every reader goes through this one walk: the calendar, home and its statistics, reminders, linked housemates' requests, the assistant.

A day that has passed with nothing stored about it is a day missed, and "needs attention" lists those however long ago. Walking a series from its first day on every page would cost more each year it runs, so **a series keeps the first day that may still have nothing stored** (`events.unsaved_from`, read as `event.unsaved_since`): every scheduled day before it has a row, whatever its status. A day saved at that point moves it on to the next day without a row; a day deleted, moved or restored, or a new rule, start or set of times, moves it back. It is a lower bound, never a promise: a writer that can't tell moves it back, and a series nothing was saved about yet reads from its first day. The model keeps it for every writer (`Occurrence`'s and `Event`'s own callbacks, `Occurrence.delete_with_children` for the bulk path), and it never touches the series' `updated_at`.

## A kind's own fields: a row for the series, a row for a day that differs

Each kind has its own table of fields: `task_details`, `appointment_details`, `medication_details`, and so on (`Details::Base`). There are two kinds of row:
- **The series' row** (`occurrence_id` NULL) holds the kind's fields for every day.
- **A day's override row** exists only where that day differs, and a NULL in it means "as the series". `occurrence.details` reads the day's row where it has one, else the series'. Its key to the day takes the series as well, so the database refuses a row that pairs a day with another series.

A universal field (title, notes, place, time) works the same way, on `occurrences` itself: the day's own value where set, else the series'. Both rows share the one rule, `InheritsFromSeries`: `inherits` names the fields, and `assign_own` writes a value only where it differs from the series.

So a weekly appointment whose visit on the 14th is with a different doctor stores one override row for the 14th, holding only the doctor. Every other week keeps following the series.

## Saving: this day, or the whole series

Every save goes through one form object per kind, `Occurrences::FormSave.for(type)`. The controllers, linked housemates' approvals and the assistant all use it. It takes plain data: the kinds' controllers permit what a form may send (`FormSave.permitted_fields`), and a request held for an owner's OK keeps the same data to save later. Its parts are small objects of their own: the series' rule, collection, times and reminders as the form sent them (`SeriesShape`), what the form changes against what the day read (`Changes`), and what a held request carries and shows its owner (`Hold`).

- **A one-off** writes its series, because its day *is* the series.
- **A day of a repeating series** writes itself, unless the form says "The whole series".
- **A day stores only what differs from its series.** A value equal to the series' is stored as NULL, so the day keeps following the series if it changes later.
- **"The whole series"** takes only what was changed on that day's form, and the day then follows the series again. A field counts as changed when its value differs as the model reads it: the form's "14:00" is a saved 14:00, its "50" a saved 50.00. What is saved is read once, when the form is built, before the save assigns anything. So a day's own values, which its form shows, stay the day's.
- **A day's form carries two versions**, the day's and its series', since it shows the series' values where the day has none of its own ([two people editing the same thing](sharing-and-links.md#two-people-editing-the-same-thing)). The save reads both under their rows' locks before it writes, and when either moved since the form was drawn it writes nothing and the form comes back saying who saved meanwhile. Another day of the same series saved meanwhile crosses nothing. A held request and the assistant send no versions, so their saves aren't checked.

A new series is made by `Occurrences::Create`. Deleting a day or a whole series goes through `Occurrences::Destroy`:
- a day of a repeating series becomes an exclusion;
- a one-off or a whole series is purged with all its days in a few statements (`Events::Purge`, the same path deleting a person takes).

Those are the only paths: a series and its days declare no `dependent:` options, so a stray `destroy` fails on a foreign key rather than half-remove something.

## A done day is a record

Editing a repeating series changes what is still to come, never what happened. When the series' title, place, time or duration changes, every completed day that read it from the series keeps the old value as its own. The same holds for the kind's *recorded* fields (`Details::Base.recorded`: a payment's amount, a dose's quantity, who a visit was with) and its lists (a meal's recipes, a dose's planned supplies). Model callbacks do it, so every writer gets it, the assistant and an undo included.

The schedule itself is kept the same way, through one service, `Events::Reschedule`. A series projects its days from its rule, so a new rule or new times written onto a series with a past would project days it never had (Tuesdays for the weeks that were Mondays, a 09:00 dose for every morning taken at 08:00) and read them as missed. Instead the series ends the day before the change and goes on as a new series under the new rule (`Event#continuation`), which takes over its shares and reminders. The change goes on from today, or from the day after the series' last done day when that is today or later: a dose taken this morning stays on the record, and the new times start tomorrow rather than beside it. The new series counts from the old one's first day, so a fortnightly series keeps its weeks and a monthly one its day of the month. A series whose days are all ahead takes the change in place, and taking the repeat away from a series with a past stops it there rather than leaving only its first day. Every writer of a repeat goes through it: a day's form saved for the whole series, the assistant, and a linked housemate's request once the owner approves it.

Something has to know what changed and when. Undo and "it changed since you asked" both compare `updated_at`. So every write that changes what a day reads moves either the day's `updated_at` or its series'.

## One status for every kind

Every kind's days have the same five statuses: pending, in progress, completed, cancelled, skipped. A skipped day says why, from its kind's reasons ("refused", "not available"…). Status only changes through three methods:
- `complete!(at:)`;
- `uncomplete!`;
- `change_status!(status, reason:)`.

Each runs the kind's hooks. Cancelling a day also cancels its unpaid costs, and reopening it restores them. `change_status!` and `mark_completed!` read whether the day is done from its row, under the row's lock, before deciding whether to give back what completing it took: a page, the assistant or "resolve" may hold a copy read before a housemate took the dose. A copy of a day nobody had saved may be stale too. If a housemate saved that slot meanwhile, the copy becomes their row, so two first presses on one day don't both insert it.

**A press says which state it wants, never "the other one".** A card's circle puts the day's completion there (POST) or takes it away (DELETE), as a grocery item's row does its check, and `mark_completed!` reads the day again under its row's lock and does nothing when it already is as asked. A second tap, two housemates pressing at once, or a page that was out of date would otherwise undo each other, and each completion moves stock.

## Sections are computed, never stored

The calendar's kinds belong to the household's sections (Agenda, Healthcare, Finance, Pantry):
- **A task** is Agenda.
- **An appointment** has a kind (medical, work, social, personal, other) that decides its section: a medical visit is Healthcare, the rest Agenda. The kind also decides how the person it is with is asked for ("Provider", or "With") and what its fee is filed under.

`Event.in_section(:healthcare)` composes each kind's answer into one query.

## Costs

**A payment is a `Transaction` series like any other.** The model is named for money moving in either direction: one series is an expense for the housemate who pays and income for the one who is paid (`Transaction#kind_for(viewer)`), so "Payment" would name only half of it. What it pays for is its `about` (`Costable`), which can be a series, one day, or a supply or grocery purchase. A visit's fee is therefore an expense *about that day*. It shows inside the visit's card and moves when the visit moves.

A payment is in its household's currency. The form never asks for one: a new payment takes the household's (`Occurrences::FormSave::Transaction`), and a saved one keeps the currency it was made in. An amount has no more decimals than its currency (`Currency`): a yen amount is whole.

**An amount is stored without a sign**: the kind says which way the money went, and whatever shows or sums an amount signs it from the kind, the day's own where it has one.

**A payment between two housemates is one series with two readers.** The other side reads it through the same `accessible_by`, read-only, with its kind turned round for them, and every sum takes the viewer's side. There is no copy to keep in step.

## Reminders

Each person who has a series can ask to be reminded "N hours or days before" each of its open days (`EventReminder`). `Reminders::DispatchJob` runs every five minutes, walks the days of the series with reminders, and sends a notification, pushed to the person's devices, when a day is due in the person's own time zone. When a day is due is its kind's answer: an appointment's start, a dose's time, a meal's usual hour, otherwise the morning. A reminder is marked sent (`EventReminderDelivery`) in the same transaction that saves its notification, so a run that fails halfway leaves it for the next run, never lost. A series whose reminders raise is reported and passed over, so one broken series never holds back everyone else's.

## On the page

The calendar shows a month of **day cards** (`Views::Calendar::DayCard`), a week to a row from a desktop up, the first and last weeks filled in with the days of the months beside it (`Calendar::Month`), so no cell is blank and a day from the month before can be used like any other:
- **Order:** what is still to do comes first, urgent before low, doses by their time; done days come last.
- **The "+"** lists every kind, each in the colour of the section a new one starts in (`Event.starting_section`: an appointment starts as a medical visit).
- **Each kind's card** asks its policy what the viewer may do: tick it, open it, share it, delete the day or the series.
- **Batch loading:** `Calendar::Days` loads a month's days and everything their cards read in a fixed number of queries. Each kind declares what its cards need (`preload_for_cards`).
- **Live:** a change redraws only the cards of the days it touched, for everyone with that month open, the days shown beside it included.

---

Using it: [The calendar](../guide/calendar.md)
