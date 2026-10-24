# frozen_string_literal: true

# One day of the calendar: its date, a "+" to add any kind of event on it,
# and a card for each of its days of a series (Occurrence, saved or
# projected), drawn by its kind's card (Views::Calendar::Cards.for), or
# a line saying nothing is planned. The menus its buttons open are the
# page's (Views::Calendar::DayMenus), drawn once around its day cards.
class Views::Calendar::DayCard < Views::Base
  # occurrences: the days on this date the viewer sees
  # (Calendar::Days); viewer: the Profile looking
  # (cards ask its policies what it may do); beside: a day of the month
  # before or after the one shown, filling in its first or last week.
  def initialize(date:, occurrences:, today: false, beside: false, viewer: nil)
    @date = date
    @occurrences = occurrences
    @today = today
    @beside = beside
    @viewer = viewer
  end

  def view_template
    div(id: dom_id, class: card_classes, data: { calendar_today_target: (@today ? "today" : nil) }) do
      header
      if @occurrences.any?
        body
      else
        p(class: "day-card__empty") { t("calendar.day_card.nothing_planned") }
      end
    end
  end

  # Public: The DOM id for this day card, used by Turbo Streams to target replacements.
  def dom_id
    "day_#{@date.iso8601}"
  end

  private

  def card_classes
    classes = [ "day-card" ]
    classes << "day-card--today" if @today
    classes << "day-card--beside" if @beside
    classes.join(" ")
  end

  # A day from the month beside the one shown is named by its month, since
  # its weekday is its column's. The date is the day's heading, so a screen
  # reader can go from day to day, and is read out whole rather than as
  # the two short words shown.
  def header
    div(class: "day-card__header") do
      h2(class: "day-card__title-group") do
        span(class: "day-card__day-name", aria: { hidden: "true" }) { l(@date, format: @beside ? :month : :weekday) }
        span(class: "day-card__number", aria: { hidden: "true" }) { @date.day.to_s }
        span(class: "is-sr-only") { day_name }
      end

      add_button
    end
  end

  def day_name = l(@date, format: :day_long)

  # The "+": it opens the page's one menu of every kind (Views::Calendar::AddMenu)
  # for this day.
  def add_button
    button(
      class: "day-card__add-btn",
      type: "button",
      aria: { label: t("calendar.day_card.add_event_on", date: day_name), expanded: "false",
              controls: Views::Calendar::AddMenu::ID },
      data: Views::Calendar::AddMenu.opener_data(@date)
    ) { "+" }
  end

  def body
    div(class: "day-card__body") do
      sorted_occurrences.each { |occurrence| render_occurrence(occurrence) }
    end
  end

  # What a day is matched by across the card: its series, date and time.
  def key_of(occurrence) = [ occurrence.event_id, occurrence.date, occurrence.time_string ]

  # An expense paid for something else on this day (a visit's fee, a meal
  # out's bill) is shown inside that day's card, not as a card of its own:
  # { host's key => [ the expenses' days ] }. An expense whose host isn't on
  # this card (another day, a purchase, not shared with the viewer) stays a
  # card.
  def costs_by_host
    @costs_by_host ||= begin
      keys = @occurrences.map { |occurrence| key_of(occurrence) }.to_set

      @occurrences.each_with_object({}) do |occurrence, costs|
        host = occurrence.event.about_day(occurrence)
        next unless host && keys.include?(key_of(host))

        (costs[key_of(host)] ||= []) << occurrence
      end
    end
  end

  def standalone_occurrences
    nested = costs_by_host.values.flatten(1)
    @occurrences.reject { |occurrence| nested.any? { |cost| cost.equal?(occurrence) } }
  end

  # Days still to do first, then by priority (urgent first), then doses by
  # their time of day (one without a time after them), with a stable
  # tiebreaker on original order.
  def sorted_occurrences
    standalone_occurrences.each_with_index.sort_by do |occurrence, index|
      [
        occurrence.completed? ? 1 : 0,
        -occurrence.priority_rank,
        occurrence.time_string || "99:99",
        index
      ]
    end.map(&:first)
  end

  def render_occurrence(occurrence)
    render Views::Calendar::Cards.for(occurrence.event.class).new(
      occurrence: occurrence, viewer: @viewer, costs: costs_by_host.fetch(key_of(occurrence), [])
    )
  end
end
