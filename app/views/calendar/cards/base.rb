# frozen_string_literal: true

# A day of a series on a calendar card — saved or projected alike: the
# Occurrence answers its title, status and details either way (its own
# value, else the series'), so a card never looks anything up. Each kind's
# card (Views::Calendar::Cards.for) names its CSS block (`prefix`, "task-card")
# and draws its content; the toggle, the title link, the completion badge,
# the status, the costs paid for the day and the share / delete actions are
# the same for every kind. What the viewer may do with the day is asked of
# Occurrences::Access, never of "is it mine?".
#
#   render Views::Calendar::Cards::TaskCard.new(occurrence: day, viewer: profile, costs: [ fee_day ])
class Views::Calendar::Cards::Base < Views::Base
  include Views::Calendar::DayPaths

  # occurrence: the day; viewer: the Profile looking (cards ask its
  # policies); costs: the Transaction days paying for this day, drawn
  # inside the card (DayCard nests them).
  def initialize(occurrence:, viewer: nil, costs: [])
    @occurrence = occurrence
    @event = occurrence.event
    @viewer = viewer
    @access = Occurrences::Access.new(occurrence, viewer)
    @costs = costs
  end

  # The kind's icon, on its card, its form and wherever its series are listed.
  def self.icon = raise(NotImplementedError, "#{name}.icon")
  # A series' own, where its kind draws them differently.
  def self.icon_of(_event) = icon

  # A part of a day's card (its circle, its title), named the same each
  # time the card is drawn: a press or a save whose broadcast draws the card
  # again leaves the focus where it was.
  def self.dom_id(occurrence, part)
    [ "day", occurrence.event_id, occurrence.date.iso8601, occurrence.time_string&.delete(":"), part ].compact.join("-")
  end

  def view_template
    div(class: card_classes) do
      toggle_circle
      content
      actions
    end
  end

  private

  attr_reader :viewer, :access

  # The card's CSS block ("task-card").
  def prefix = raise(NotImplementedError, "#{self.class.name}#prefix")
  def content = raise(NotImplementedError, "#{self.class.name}#content")
  # The class of the link that opens the day's form.
  def link_class = "#{prefix}__title-link"
  def i18n_scope = @event.class.model_name.route_key

  def saved? = @occurrence.persisted?
  def completed? = @occurrence.completed?
  def status = @occurrence.status
  def details = @occurrence.details
  def title = @occurrence.event_label

  # Its block, its state, and the section whose colour its edge takes
  # (`--section-color`, set per `section--<name>` in _sections.scss).
  def card_classes
    [ prefix, saved? ? "#{prefix}--#{status}" : "#{prefix}--projected", "section--#{@occurrence.section}" ]
  end

  def form_path = day_form_path(@occurrence)

  # The circle: a press on it says the state it wants, done or not, naming
  # the item, since many sit on a calendar.
  def toggle_circle
    label = t("calendar.day_card.#{completed? ? "reopen" : "complete"}", title: title)
    render Views::Calendar::Cards::Toggle.new(occurrence: @occurrence, block: prefix, access: access, label: label)
  end

  def title_link
    a(id: self.class.dom_id(@occurrence, :title), href: form_path, class: link_class, data: { turbo_stream: true }) { title }
  end

  # How far from its date a day was done: early, late or on time.
  def completion_badge
    offset = @occurrence.days_offset
    return unless offset

    modifier, label =
      if offset.positive? then [ "early", t("#{i18n_scope}.completion.days_early", count: offset) ]
      elsif offset.negative? then [ "late", t("#{i18n_scope}.completion.days_late", count: offset.abs) ]
      else [ "on-time", t("#{i18n_scope}.completion.on_time") ]
      end

    span(class: "#{prefix}__completion #{prefix}__completion--#{modifier}") { label }
  end

  # How the day went, under every card's content: done early, late or on
  # time, else how it stands, when that says more than still to do. A day
  # still to do is the ordinary case, and its empty circle already says so.
  def outcome
    return completion_badge if completed?

    status_label unless still_to_do?
  end

  def still_to_do? = !saved? || @occurrence.pending?

  def status_label
    span(class: "#{prefix}__status #{prefix}__status--#{status}") { status_text }
  end

  def status_text = t("#{i18n_scope}.status.#{status}")

  # The days of the expenses paid for this day (a visit's fee).
  def attached_costs
    @costs.each { |cost| render Views::Calendar::Cards::AttachedCost.new(occurrence: cost, viewer: viewer) }
  end

  def actions
    render Views::Calendar::Cards::Actions.new(occurrence: @occurrence, access: access)
  end
end
