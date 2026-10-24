# frozen_string_literal: true

# A collection's page: its name, status and notes, and the series in it
# (`events`, read with their first days: Event.preload_first_occurrences),
# each opening its first day's form. Editing and sharing it are the top
# bar's, with deleting behind its "more", each for whoever may do it.
class Views::Collections::Show < Views::Base
  include Views::Calendar::DayPaths

  def initialize(collection:, viewer:, events:)
    @collection = collection
    @viewer = viewer
    @events = events
  end

  def page_title = @collection.name

  def navbar_controls
    policy = Pundit.policy!(@viewer, @collection)
    actions = []
    if policy.update?
      actions << Components::Action.new(href: routes.edit_collection_path(@collection), icon: "fa-pen", label: t("collections.show.edit"),
                                        turbo_stream: true)
    end
    if SharePolicy.new(@viewer, @collection).share?
      actions << Components::Action.new(href: routes.new_collection_share_path(collection_id: @collection.id), icon: "fa-share-nodes",
                                        label: t("collections.show.share"), turbo_stream: true)
    end
    if policy.destroy?
      actions << Components::Action.new(href: routes.collection_path(@collection), icon: "fa-trash", label: t("collections.show.destroy"),
                                        method: :delete, confirm: t("collections.confirm_destroy", name: @collection.name), danger: true)
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "collection-show section--#{@collection.section}") do
      header
      events_section
    end
  end

  private

  def wording(key) = t("collections.sections.#{@collection.section}.show.#{key}")

  def header
    render Components::PageHeader.new(title: @collection.name, subtitle: @collection.notes,
                                      back_href: collections_path(section: @collection.section), back_label: wording(:back)) do
      render Views::Collections::StatusBadge.new(status: @collection.status)
    end
  end

  def events_section
    div(class: "collection-show__events") do
      h2(class: "collection-show__events-title") { wording(:events_title) }

      if @events.any?
        @events.each { |event| render_event_row(event) }
      else
        render Components::EmptyState.new(icon: "fa-calendar-days", message: wording(:events_empty))
      end
    end
  end

  # A series, opening the form of its first day: saved, or still projected.
  def render_event_row(event)
    occurrence = event.first_occurrence
    a(href: occurrence_path(occurrence), class: "collection-event-row section--#{event.section}", data: { turbo_stream: true }) do
      render Components::Icon.new(Views::Calendar::Cards.icon_of(event), class: "collection-event-row__icon")
      span(class: "collection-event-row__type") { t("calendar.day_card.event_types.#{event.class.route_key}") }
      span(class: "collection-event-row__label") { occurrence.event_label }
      span(class: "collection-event-row__date") { l(event.starts_on, format: :long) }
    end
  end

  def occurrence_path(occurrence) = day_form_path(occurrence)
end
