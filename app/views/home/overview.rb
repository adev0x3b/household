# frozen_string_literal: true

# The home page, top to bottom:
#   1. "Needs attention" across every section (hidden when empty)
#   2. today, as the calendar's own day card: items are completed, added
#      and edited right here, and it updates live like the calendar does
#   3. one card per section with its headline figure, opening its page
#   4. what's planned for the next 7 days, each item opening in a modal
# Always everyone's data as of today: there is no period or member to pick,
# and the section cards are the way to the other pages, so the tabs stay
# off this one. A household with nothing on any calendar yet sees its
# first steps instead, since figures of nothing say nothing.
class Views::Home::Overview < Views::Home::Base
  def self.key = :overview
  def self.icon = "fa-house"

  private

  def page_header = render(Components::PageHeader.new(title: t("home.overview.title")))

  def content
    return render(Views::Home::FirstSteps.new) if @home.empty?

    attention(@home.attention)
    today_card
    section_cards
    upcoming
  end

  def today_card
    today = @home.today
    viewer = @home.audience.viewer

    section(class: "home__today", aria: { label: t("home.today") }) do
      div(data: {
            controller: "calendar-subscription",
            calendar_subscription_profile_id_value: viewer.id,
            calendar_subscription_year_value: today.year,
            calendar_subscription_month_value: today.month
          }) do
        render Views::Calendar::DayMenus.new do
          render Views::Calendar::DayCard.new(
            date: today, occurrences: @home.today_entries, today: true, viewer: viewer,
          )
        end
      end
    end
  end

  def section_cards
    section(class: "home__sections", aria: { label: t("home.overview.sections") }) do
      agenda_card
      healthcare_card
      finance_card
      pantry_card
    end
  end

  def agenda_card
    tasks = @home.agenda.tasks
    progress = tasks.today_progress
    overdue = tasks.overdue_metric.value

    section_card(
      :agenda,
      value: progress[:total].zero? ? format_figure(nil, :count) : t("home.overview.cards.agenda.value", **progress),
      caption: t(progress[:total].zero? ? "home.overview.cards.agenda.none_today" : "home.overview.cards.agenda.caption"),
      note: (t("home.overview.cards.agenda.overdue", count: overdue) if overdue.positive?),
    )
  end

  def healthcare_card
    medications = @home.healthcare.medications
    missed = medications.missed_metric.value.to_i

    section_card(
      :healthcare,
      value: format_figure(medications.adherence_metric.value, :percent),
      caption: t("home.overview.cards.healthcare.caption"),
      note: (t("home.overview.cards.healthcare.missed", count: missed) if missed.positive?),
    )
  end

  def finance_card
    metric = @home.finance.cash_flow.net_cash_flow_metric

    section_card(:finance, value: format_figure(metric.value, metric.format), caption: t("home.overview.cards.finance.caption"))
  end

  def pantry_card
    to_buy = @home.pantry.groceries.open_items_metric.value

    section_card(
      :pantry,
      value: format_figure(@home.pantry.meals.planned_metric.value, :count),
      caption: t("home.overview.cards.pantry.caption"),
      note: (t("home.overview.cards.pantry.to_buy", count: to_buy) if to_buy.positive?),
    )
  end

  def section_card(key, value:, caption:, note: nil)
    icon = Views::Home::Pages::SECTIONS.fetch(key.to_s).icon

    render Views::Home::SectionCard.new(
      title: t("home.tabs.#{key}"), icon: icon, href: home_section_path(section: key),
      value: value, caption: caption, note: note, section: key,
    )
  end

  # The next 7 days, every section together.
  def upcoming
    upcoming = @home.upcoming

    detail_report(:upcoming, icon: "fa-calendar-week", empty: !upcoming.any?) do
      render Views::Home::AgendaList.new(upcoming: upcoming)
    end
  end
end
