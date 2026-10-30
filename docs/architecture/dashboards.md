# Dashboards: home and the sections' statistics

[Documentation](../README.md) › [Architecture](README.md)

The landing page (`/`) is the **home dashboard**: what needs attention, today, and the week ahead. Each section of the household (Agenda, Healthcare, Finance, Pantry) has a page of its own under `/home/<section>`. It shows what needs attention there, up to four headline figures, what's next, and then the section's statistics, for a period and a member picked on that page. There are no separate statistics pages. **Home never sends the reader elsewhere to act:** its rows open the item's own form in place. A household with nothing on any calendar yet is offered its first steps (the calendar, inviting its people) instead of empty figures.

## Deciding what to measure

Each headline figure answers a question someone would act on, and is defined before it is built, down to what an empty period shows:

```
Metric:       Dose adherence
Question:     Am I taking my medication as prescribed?
Numerator:    doses taken (status completed), dated in the period, due by today
Denominator:  doses due = taken + skipped + missed (cancelled and future excluded)
Time basis:   the scheduled day, not when it was ticked
Polarity:     higher is better · target 80%
Empty means:  nothing was due, so show "—", never 0%
```

Each edge of the definition is a test of its report, and the figure's hint on the page says it in one sentence.

The rules that follow from that:
- **Rates, not bare counts:** a figure says "12 of 15 due", never "12 taken" alone.
- **A past day nobody ticked is missed.** It exists even with no row (see [the calendar](calendar.md)), and the ledger counts it.
- **Every figure is compared** with the previous period of the same length, as a difference: three more, €30 less, four points up. A count or an amount is never put as a percentage of what it was.
- **At most four headline figures per section.** Everything else goes in a report below them.
- **Money is never summed across currencies.**
- **A transfer to savings is not spending.** It is money the household keeps, so it leaves Spending, Largest expenses and Net cash flow alone (`Transaction::Details.cash_categories`) and feeds the savings rate.
- **No database words reach the page:** the reader sees *taken*, *missed*, *upcoming*, *spent*.

## The reports

The figures come from one namespace, `Reports::` (`app/reports`).

**The building blocks:**
- `Period`: the dates asked for, the period before them, and the buckets a trend chart plots (a day, a week or a month each, by the length of the range). `Period.recent`, `.ahead` and `.from_today` are the spans a home page reads as of today whatever period is picked: the last 30 days, the next 7, and today with them.
- `Audience`: whose series count, the viewer's or one member's.
- `Window`: a page's series, days and money sums, loaded once and shared by its reports.
- `Metric`, `Money` and `Chart`: a figure, an amount in the household's currency (shown with the decimals that currency has, `Currency`), a chart's data.
- `MoneyFlow`: what was spent, received or netted over a period, shown in the currency most of it moved in, with the others listed beside it. `CategoryChart` stacks a flow by category, and `AmountShare` lists its parts with their share.
- `OccurrenceLedger`: every day in a range, saved or not, with its status, missed days included. Each entry answers for itself whether it was taken, is due or is still to come. `TimingChart` draws how early or late the taken ones were done.

**Each section's `Dashboard`** (`Reports::Agenda::Dashboard`, `Reports::Healthcare::Dashboard`, `Reports::Finance::Dashboard`, `Reports::Pantry::Dashboard`) builds that section's reports, one per area of it (the Agenda's tasks and its appointments, the pantry's meals and its groceries), once each, over the page's window. Each also builds the section's "needs attention" items. `Reports::Home` is the facade the home page reads. A page's headline figures are its view's: it picks them from the reports, with their icons and footnotes.

**How the queries are written:**
- **One load per page.** A report takes the page's `Window`, so a page doesn't load the same days four times.
- **Scope through the audience**, never a bare profile: it names each series the viewer reads once, however many ways it reaches them, so a sum over it counts each once.
- **Group and sum in SQL.** N+1 detection runs on every request in the tests, so a per-record loop shows up.
- **A fixed cost per page.** Home reads per kind of item and per list, never per series or day: twice the household costs the same queries. `test/integration/home_page_weight_test.rb` holds it, and holds the overview to its budget.
- **Inject `today:`** into every report that reads the clock, so its tests are deterministic.
- **Reports return values, never markup or routes.** The Phlex components draw them.

## The page

- **The pages are listed once,** in `Views::Home::Pages`, which the routes, the controller and the tabs read. Each page's view names itself, puts the period under its tabs and lists its reports, one `Views::Home::Reports` view each.
- **The period and the member** are GET controls that revisit the same page with `data-turbo-action="replace"`. Turbo treats that as a page refresh: the page is morphed in place and the reader's scroll is kept.
- **The reports** are lazy `turbo-frame`s, one request each (`/home/<section>/reports/<name>`), so a slow report doesn't hold up the first paint. They carry `refresh: :morph`, so a page refresh reloads them in place instead of leaving them on a spinner.
- **After a change made in place**, say a task ticked on today's card, the home page reloads its frame (`home_refresh_controller.js`). Every figure is fresh, and nothing collapses to placeholders.
- **After a change made elsewhere**, by a housemate or on another device, the overview's today card hears it over the calendar's live updates for the month, and the overview reloads its frame the same way, once a burst of updated days has settled.
- **Charts** are Chart.js 4, drawn by one Stimulus controller (`chart_controller.js`) from a spec Ruby builds. Its colours are tokens the stylesheet defines, and its numbers are formatted in the reader's language. No other file knows Chart.js.

## Needs attention

Every section's "needs attention" item is one `Reports::AttentionItem`: a missed dose, a supply about to run out, a payment due, a lab value out of range. Each has a severity and a link that opens the item in place: the day it is about, for a supply a new purchase of it, for a batch its own purchase. Its kind names the sentence that words it, and the report hands over what that sentence fills in (a lab value, the ingredients short), so the list draws every kind the same way. Home gathers them from every section, sorted by severity.

**An item about a day that passed unrecorded can be settled from the list itself.** The item says so (`resolvable`), and a press beside it marks every such day of its series as skipped, through `Attention::Resolve`: what was never recorded stays unrecorded, on the record as skipped, and the series leaves the list. The list's footer settles every such item of the page's list at once, after a confirmation. Both go through `AttentionResolutionsController` and come back to the page, which draws itself again. Each day is checked with its own policy: the press is offered only to someone who may change the day outright, never to a linked housemate who would have to ask, since the list promises to settle, not to send a request. What is still to come, was already skipped, or is about a supply or a value is not settled this way.

**Every day that has passed and is still to do counts, however long ago**: a task, an appointment of any kind, a dose, a meal, a lab result or a payment that is neither done, cancelled nor skipped. The list shows each series once, at its newest such day, with how many it has ("6 times"); urgent items first, then the nearest to today, six to a page with their own page links. `Reports::Unfinished` reads them apart from the page's window, which loads a span whole for the figures: it reads however long ago, but loads only the unfinished days, looks for a day nothing was saved about only from the first day its series may have one (`Event#unsaved_since`, see [calendar.md](calendar.md)), and learns which of those were saved from their dates alone. The window holds one per page, and the kinds a page names are read together.

---

Using it: [Home](../guide/home.md)
