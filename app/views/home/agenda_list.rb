# frozen_string_literal: true

# The next days at a glance (a Reports::Upcoming): one group per day, one
# line per thing still to do, with the icon and colour of its series' kind
# and section (an appointment's by its kind). A line opens its day in a
# modal, in place.
#
# A page at a time, in its own frame: the page links (?upcoming_page=)
# load the overview's FRAME alone (HomeController#show answers it with
# this component only) and advance the URL, so a reload, or the home page
# refreshing after a change, stays on the page being read.
class Views::Home::AgendaList < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME = "home-upcoming"

  def initialize(upcoming:)
    @upcoming = upcoming
  end

  def view_template
    turbo_frame_tag(FRAME) do
      ol(class: "home-agenda") do
        @upcoming.days.each { |day| day_group(day) }
      end
      render Components::Pagination.new(collection: @upcoming.page, turbo_frame: FRAME, turbo_action: "advance", param_name: :upcoming_page,
                                        list: t("home.overview.upcoming.title"))
    end
  end

  private

  def day_group(day)
    li(class: "home-agenda__day") do
      span(class: "home-agenda__date") { l(day.date, format: :day) }
      ul(class: "home-agenda__items") do
        day.items.each { |item| li { line(item) } }
      end
    end
  end

  def line(item)
    event = item.event
    render Views::Home::OccurrenceLink.new(occurrence: item.occurrence, class: "home-agenda__item") do
      render Components::Icon.new(Views::Calendar::Cards.icon_of(event),
                                  class: [ "home-agenda__icon", ("section--#{event.section}" if event.section) ])
      span { item.label }
      time = time_label(item)
      span(class: "home-agenda__time") { time } if time
    end
  end

  # A dose's slot ("with breakfast", "08:00"), else an appointment's start.
  def time_label(item)
    item.time ? item.occurrence.time_label : item.occurrence.formatted_start_time
  end
end
