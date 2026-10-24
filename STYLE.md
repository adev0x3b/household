# Style guide

How code in this repository is written. Formatting is left to the linters. This page covers what they can't check: what a comment is for, the few conventions the codebase has picked between equally valid options, and how objects are shaped.

Every rule comes with a good and a bad example. The examples are written for this page and use the app's vocabulary, so they read like the code around them, but they are illustrations rather than excerpts.

## Comments

A comment explains **why** the code is the way it is. The code already says what it does, and a comment that repeats it is one more thing to keep in step.

- **Why, never what.** Write a comment when a reader would otherwise ask "why not the obvious way?": a constraint from outside the code, a trade-off that was weighed, a behaviour of a library or the browser that isn't visible from here.
- **Plain, full sentences.** Write the way you would explain it to a colleague, with articles and verbs. A comment is not a slogan or a riddle.
- **Nothing that goes stale.** No dates, no ticket, audit or ADR numbers, no story of the bug that led here (that belongs in the commit message), and no counts or lists of other files ("the twenty tools", "used by A, B and C"). Link to a document only when the reader genuinely needs it to understand the line.
- **A class header only when the name isn't enough,** and then one to three lines. Most classes need none.
- **No banners or dividers.** If a file needs sections, it probably wants to be two files.
- **Delete a comment that is wrong.** A wrong comment does more harm than a missing one.

Good:

```ruby
# Doses are drawn from stock when they are taken, not when they are
# scheduled, so a skipped dose never empties the cupboard.
def on_occurrence_completed(occurrence)
  supply.draw!(occurrence.quantity)
end
```

Bad:

```ruby
# ── Completion ──────────────────────────────────────────────
# The dose is taken: stock moves (2026-10-04, after the Ibuprofen bug).
# Called by Occurrence. See ADR 0017.
def on_occurrence_completed(occurrence)
  supply.draw!(occurrence.quantity) # draw from the supply
end
```

The bad version has a banner, a date, a bug story, a cross-reference that will drift, and a trailing comment that restates the code. It never says the one thing a reader needs: why stock moves on completion rather than on scheduling.

## Code conventions

### One entry point for a service

A service is a verb with one class method, `.call`, taking its subject first and everything else as keywords. A service that can fail in a way its caller expects returns a `ServiceResult`; one that can't returns its subject. A form object keeps ActiveModel's contract instead (`#save` returns true or false, with `errors`), and no service reaches into another object's private methods with `send`.

Good:

```ruby
Links::Decline.call(link, by: current_profile)
Households::Destroy.call(household)
```

Bad:

```ruby
Links::Decline.new(link).call(current_profile)
Links::Decliner.run(link, current_profile)
```

When the work needs private helpers, `.call` builds an instance and calls it. The caller still sees only `.call`.

### When to write an endless method

Use an endless `def` for a method that is one expression and fits on one line. Anything with a condition, more than one step, or a line break gets a regular `def`.

Good:

```ruby
def overdue? = due_on < Date.current

def summary
  return t(".none") if items.empty?

  t(".count", count: items.size)
end
```

Bad:

```ruby
def summary = items.empty? ? t(".none") : t(".count", count: items.size)

def label = [ title,
              (time_of_day && l(time_of_day, format: :short)) ].compact.join(" · ")
```

### `t(` in views and controllers

Views, components and controllers translate with `t(` and the key written out whole (`t("books.index.title")`). A key in full can be found with a search, and a Phlex component's `t` is `I18n.t`, which resolves no lazy `.title` key. `I18n.t` is for code that has no view or controller around it: models, jobs and services.

Good:

```ruby
h1 { t("books.index.title") }
redirect_to books_path, notice: t("books.notices.created"), status: :see_other
```

Bad:

```ruby
h1 { t(".title") }
redirect_to books_path, notice: I18n.t("books.notices.created"), status: :see_other
```

### Fixtures are people

Fixtures are named after who or what they are, so a test reads as a story: `profiles(:alice)` shares a list with `profiles(:bob)`, and `profiles(:carol)` lives in another household. Generic names such as `one` and `two` say nothing about the record's role.

Good:

```ruby
test "a housemate sees a shared list" do
  sign_in profiles(:bob)
  get grocery_list_path(grocery_lists(:alices_weekly_shop))
  assert_response :success
end
```

Bad:

```ruby
test "a housemate sees a shared list" do
  sign_in profiles(:two)
  get grocery_list_path(grocery_lists(:one))
  assert_response :success
end
```

## Design: small objects that each do one thing

The aim is a modular design of small objects that are easy to read and easy to use. When a rule below and a shorter diff disagree, the rule wins.

### An object, not a mixin

A module may share behaviour, never state. When a class is split into modules that read each other's instance variables, the coupling is still there, only harder to see. Give each part its own class with its own inputs instead.

Good:

```ruby
class Operations::Update
  def call
    cost = Cost.new(@payload, currency: @household.currency)
    stock = StockChange.new(@occurrence, uses: @payload.uses)
    apply(cost.amount, stock.moves)
  end
end
```

Bad:

```ruby
class Operations::Update
  include CostHandling   # sets @cost
  include StockHandling  # reads @cost and sets @uses

  def call
    prepare_cost
    prepare_stock
    apply
  end
end
```

### Polymorphism, not string dispatch

Behaviour that differs by kind is a method on the kind. A branch on `kind == "..."` or `type == "..."` grows a new arm with every new kind, and the arms drift. Statuses are symbols or small objects, never bare strings.

Good:

```ruby
class Medication < Event
  def self.section = :healthcare
end

event.class.section
```

Bad:

```ruby
def section_for(event)
  case event.type
  when "Medication" then :healthcare
  when "Meal" then :pantry
  else :agenda
  end
end
```

### A plain object, not a framework

Behaviour built from `define_method`, prepended callbacks or reflection on method parameters is hard to read, hard to search for and hard to debug. Write the class out, even when it is longer.

Good:

```ruby
class Reports::Healthcare::Dashboard
  def medications
    @medications ||= Medications.new(audience: @audience, period: @period, window: @window)
  end

  def supplies
    @supplies ||= Supplies.new(audience: @audience, today: @today)
  end
end
```

Bad:

```ruby
class Reports::Healthcare::Dashboard
  def reports
    REPORTS.map do |report|
      wanted = report.instance_method(:initialize).parameters.map(&:last)
      report.new(**dependencies.slice(*wanted))
    end
  end
end
```

### Dependencies point inward

Models and services never reach into controllers, tools or views. A component, the kit every area shares, never names a view; a view may draw any component, and another area's view. A component that needs a limit reads it from the model or from configuration, not from a controller constant. A view never runs a query; whoever renders it hands it what it shows. The one exception is a picker: a form's options (the units, the ingredients, the collections to choose from) come from a lookup the model names, such as `Unit.names_for(profile)`, because every form that offers them would otherwise load the same list in its controller.

Good:

```ruby
class Message < ApplicationRecord
  MAX_LENGTH = 4_000
end

textarea(maxlength: Message::MAX_LENGTH)

datalist(id: "units-datalist") { Unit.names_for(@profile).each { |name| option(value: name) } }
```

Bad:

```ruby
textarea(maxlength: MessagesController::MAX_LENGTH)

def view_template
  Ingredient.where(household: @household).order(:name).each { |ingredient| option(value: ingredient.name) }
end
```

### One job per object

Each class has one reason to change. A method that keeps more than a handful of instance variables, or a model that also rate-limits and enforces quotas, is a new class waiting to be named. Long methods are split into named steps.

Good:

```ruby
class Uploads::Quota
  def initialize(household) = @household = household

  def allows?(bytes) = used + bytes <= limit
end
```

Bad:

```ruby
class Household < ApplicationRecord
  def assistant_rate_limited? = Rails.cache.read("assistant:#{id}").to_i > 30
  def upload_quota_left = upload_limit - uploads.sum(:byte_size)
  # ... and everything else a household is
end
```

### Explicit over clever

The plain version wins, even when it is longer. A reader should never have to stop and decode a line.

Good:

```ruby
def pull_request
  return @pull_request if defined?(@pull_request)

  @pull_request = github.pull_request_for(commit)
end

def submit
  return if draft.blank?

  draft.submit!
end
```

Bad:

```ruby
def pull_request = (@pull_request ||= [ github.pull_request_for(commit) ]).first

def submit
  draft.presence or return
  draft.submit!
end
```
