# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  SECTIONS = {
    "agenda" => %w[progress timing appointments],
    "healthcare" => %w[medications appointments labs spending supplies],
    "finance" => %w[spending income],
    "pantry" => %w[meals groceries]
  }.freeze

  setup do
    @profile = profiles(:carol)
    sign_in @profile
  end

  teardown { I18n.locale = I18n.default_locale }

  test "the root is the overview: tabs, today's day card, one card per section and the next 7 days" do
    task!(profile: @profile, date: Date.current, title: "Water the plants")
    tomorrow = task!(profile: @profile, date: Date.current + 1, title: "Call the plumber")
    bins = weekly_event(profile: @profile, type: Task, starts_on: Date.current - 5, title: "Take out the bins") # next on today + 2

    get root_path

    assert_response :success
    assert_select "turbo-frame#home-page[target=_top][refresh=morph][data-controller=home-refresh]"
    # A day changed elsewhere reaches the today card, and the page reloads around it.
    assert_select "turbo-frame#home-page[data-action='calendar-subscription:changed->home-refresh#reload']"
    # Turbo 8 page refreshes: a filter's `replace` visit morphs the page and keeps the scroll.
    assert_select "head meta[name=turbo-refresh-method][content=morph]"
    assert_select "head meta[name=turbo-refresh-scroll][content=preserve]"
    # Every confirmation asks in the app's own dialog, which the layout carries once.
    assert_select "body > dialog#confirm_dialog", 1
    # Back asks for the page as it is now, and the page catches up after a dropped connection.
    assert_select "head meta[name=turbo-cache-control][content=no-cache]"
    assert_select "body[data-controller~=catch-up]"
    # The focus a live change takes away is put back (focus_keeper_controller.js).
    assert_select "body[data-controller~=focus-keeper] main#content[data-focus-keeper-target=content]"
    assert_select "#toast-container[data-catch-up-target=kept]"
    assert_select "turbo-frame#modals[data-catch-up-target=kept]"
    assert_select "h1", I18n.t("home.overview.title")
    assert_select ".tabs-nav", 0, "the section cards are the way to the other pages"
    assert_select "[data-controller=calendar-subscription] #day_#{Date.current.iso8601}", text: /Water the plants/
    # Its "+" and its cards' "more" open the menus drawn once beside it, as on the calendar.
    assert_select "[data-controller='card-menu day-add'] #day_#{Date.current.iso8601} ~ #card_menu ~ #day_add_menu"
    assert_select "a.home-section-card", 4
    SECTIONS.each_key { |section| assert_select "a.home-section-card[href='#{home_section_path(section: section)}']" }
    assert_select "#home-overview-upcoming a.home-agenda__item[data-turbo-stream][href='#{edit_event_day_path(tomorrow.event, tomorrow.date)}']", text: /Call the plumber/
    projected = edit_event_day_path(bins, Date.current + 2)
    assert_select "a.home-agenda__item[href='#{projected}'] .home-agenda__icon.fa-clipboard-list.section--agenda"
    assert_select ".stat-period-selector", 0
  end

  test "a household with nothing on any calendar yet is offered its first steps instead of figures" do
    sign_in profiles(:outsider)

    get root_path

    assert_select ".home-first-steps a.button[href='#{calendar_path}']", text: /Open the calendar/
    assert_select ".home-first-steps a[href='#{household_path}']", text: "Invite your housemates"
    assert_select ".home-section-card", 0
    assert_select ".day-card", 0
  end

  test "the next 7 days come a page at a time, each page loading the list's frame alone and advancing the URL" do
    (Reports::Upcoming::PER_PAGE + 1).times { |index| task!(profile: @profile, date: Date.current + 1, title: format("Errand %02d", index)) }

    get root_path

    assert_select "turbo-frame#home-upcoming .home-agenda__item", Reports::Upcoming::PER_PAGE
    assert_select "turbo-frame#home-upcoming nav.pagination a[data-turbo-frame=home-upcoming][data-turbo-action=advance][href='#{root_path(upcoming_page: 2)}']"
    assert_select "turbo-frame#home-upcoming nav.pagination[aria-label=?]", "Pages of “Next 7 days”"

    get root_path(upcoming_page: 2), headers: { "Turbo-Frame" => "home-upcoming" }

    assert_response :success
    assert_select "turbo-frame#home-upcoming .home-agenda__item", count: 1, text: /Errand 12/
    assert_select "#home-page", 0
    assert_select ".stat-attention", 0
  end

  test "what needs attention opens in place: the day's modal, or a new day of a repeating series" do
    late = task!(profile: @profile, date: Date.current - 1, title: "Pay the rent")
    series = weekly_event(profile: @profile, type: Medication, starts_on: Date.current - 9)
    medication!(profile: @profile, date: Date.current - 9, status: :completed, event: series)

    get root_path

    assert_select ".stat-attention__item", 2
    assert_select ".stat-attention__item--warning a[data-turbo-stream][href='#{edit_event_day_path(late.event, late.date)}']", text: /Pay the rent/
    missed = edit_event_day_path(series, Date.current - 2)
    assert_select ".stat-attention__item--critical a[data-turbo-stream][href='#{missed}']"
  end

  test "an overdue dose of several a day opens that dose" do
    @profile.update!(time_zone: "UTC")
    first = timed_medication!(profile: @profile, starts_on: Date.current, times: %w[00:00 00:01], name: "Metformin")

    travel_to(Time.current.utc.change(hour: 23)) { get root_path }

    assert_select ".stat-attention__item a[href='#{edit_event_day_path(first.event, first.date, time: "00:00")}']", text: /Metformin/
    second = edit_event_day_path(first.event, Date.current, time: "00:01")
    assert_select ".stat-attention__item a[href='#{second}']", text: /Metformin/
  end

  test "every section page has its figures, the period selector and one lazy frame per report" do
    SECTIONS.each do |section, names|
      get home_section_path(section: section)

      assert_response :success
      assert_select ".tabs-nav__tab", 5
      assert_select ".tabs-nav__tab.is-current", text: /#{Regexp.escape(I18n.t("home.tabs.#{section}"))}/
      assert_select ".stat-tile", 4
      assert_select ".statistics__heading .stat-period-selector form[action='#{home_section_path(section: section)}']"
      assert_select "turbo-frame.statistics__frame", names.size
      names.each do |name|
        src = home_report_path(section: section, name: name, **Reports::Period.recent(today: Date.current).to_param)
        assert_select "turbo-frame#stat-report-#{name}[loading=lazy][refresh=morph][src='#{src}']"
      end
    end
  end

  test "a figure says what its number needs: its target, what is still scheduled, what moved in other currencies" do
    expense!(profile: @profile, date: Date.current - 1, cents: 1000)
    expense!(profile: @profile, date: Date.current - 2, cents: 300, currency: "USD")
    expense!(profile: @profile, date: Date.current, cents: 200, status: :pending)

    get home_section_path(section: "healthcare")

    assert_select ".stat-tile__footnote", text: I18n.t("home.kpis.target", target: "80%")
    assert_select ".stat-tile__footnote", text: /\A\+ .+ still scheduled · Also .+\z/

    get home_section_path(section: "finance")

    assert_select ".stat-tile__footnote", text: I18n.t("home.kpis.target", target: "20%")
    assert_select ".stat-tile__footnote", text: /\AAlso /
  end

  test "a picked period is kept by the frames and named by the page's selector, not repeated as a title" do
    get home_section_path(section: "finance", start_date: "2025-01-01", end_date: "2025-03-31")

    assert_select ".statistics__title, .statistics__period", 0
    assert_select ".statistics__header h1.page-title", I18n.t("home.finance.title")
    assert_select "turbo-frame#stat-report-income[src*='start_date=2025-01-01'][src*='end_date=2025-03-31']"
    assert_select ".stat-period-selector__name", "January 1, 2025 – March 31, 2025"
    assert_select ".stat-period-selector input[name=start_date][value='2025-01-01']"
  end

  test "each report renders inside its own frame without the layout" do
    SECTIONS.merge("finance" => %w[spending income settlements]).each do |section, names|
      names.each do |name|
        get home_report_path(section: section, name: name, start_date: "2025-01-01", end_date: "2025-03-31")

        assert_response :success, "#{section}/#{name}"
        assert_select "turbo-frame#stat-report-#{name}"
        assert_select "nav.navbar-sheet", 0
      end
    end
  end

  test "reports with data render their charts and tables" do
    today = Date.current
    task!(profile: @profile, date: today - 2, status: :completed, priority: :high)
    task!(profile: @profile, date: today - 3)
    appointment!(profile: @profile, date: today - 2, kind: :social, status: :completed, title: "Dinner")
    appointment!(profile: @profile, date: today - 4, kind: :medical, status: :completed, counterpart: "Dr Moretti")
    therapy = Collection.create!(profile: @profile, name: "B12")
    dose = medication!(profile: @profile, date: today - 2, status: :completed)
    dose.event.update!(collection: therapy)
    expense!(profile: @profile, date: today - 2, cents: 3000, about: dose)
    meal_on(@profile, today - 2, title: "Soup", meal_type: :lunch, status: :completed)
    expense!(profile: @profile, date: today - 2, cents: 5000, category: :groceries)
    income!(profile: @profile, date: today - 3, cents: 90_000)
    ingredient_purchase!(profile: @profile, name: "Flour", purchased_on: today - 3)

    { "agenda" => %w[progress timing appointments], "pantry" => %w[meals groceries],
      "healthcare" => %w[medications appointments spending], "finance" => %w[spending income] }.each do |section, names|
      names.each do |name|
        get home_report_path(section: section, name: name)

        assert_select "canvas[data-controller=chart]", { minimum: 1 }, "#{section}/#{name}"
        assert_select ".stat-table__row", { minimum: 1 }, "#{section}/#{name}"
        assert_select "body", text: /translation missing/i, count: 0
      end
    end

    get home_report_path(section: "healthcare", name: "spending")
    assert_select ".stat-table__row", text: /B12/
    get home_report_path(section: "healthcare", name: "appointments")
    assert_select ".stat-table__row", text: /Dr Moretti/
  end

  test "the agenda lists tasks coming up and overdue, and appointments coming up, each opening its modal" do
    late = task!(profile: @profile, date: Date.current - 1, title: "Pay the rent", priority: :urgent)
    task!(profile: @profile, date: Date.current + 1, title: "Call the plumber")
    dinner = appointment!(profile: @profile, date: Date.current + 2, kind: :social, title: "Dinner", counterpart: "Giulia")
    appointment!(profile: @profile, date: Date.current + 2, kind: :medical, title: "Checkup")

    get home_section_path(section: "agenda")

    assert_select "#home-agenda-upcoming .stat-table__row", text: /Call the plumber/
    assert_select "#home-agenda-overdue .stat-table__row a[data-turbo-stream][href='#{edit_event_day_path(late.event, late.date)}']", text: "Pay the rent"
    assert_select "#home-agenda-next_appointments .stat-table__row", 1
    assert_select "#home-agenda-next_appointments .stat-table__row a[data-turbo-stream][href='#{edit_event_day_path(dinner.event, dinner.date)}']", text: "Dinner"
    assert_select "#home-agenda-next_appointments .stat-table__row", text: /Giulia/
  end

  test "pantry shows empty states when nothing is planned or listed, and active lists otherwise" do
    get home_section_path(section: "pantry")

    assert_select "#home-pantry-short_meals .empty-state"
    assert_select "#home-pantry-lists .empty-state"

    list = GroceryList.create!(profile: @profile, name: "Weekly")
    list.grocery_list_items.create!(ingredient_name: "Milk", quantity: 1)
    get home_section_path(section: "pantry")

    assert_select "#home-pantry-lists a[href='#{grocery_list_path(list)}']", text: "Weekly"
  end

  test "finance adds settlements, and the member filter appears, only when data is shared" do
    get home_section_path(section: "finance")
    assert_select "turbo-frame#stat-report-settlements", 0
    assert_select "form.stat-member-filter", 0

    shared = expense!(profile: profiles(:alice), date: Date.current - 1, cents: 500)
    EventShare.create!(event: shared.event, profile: @profile)
    get home_section_path(section: "finance")

    assert_select "turbo-frame#stat-report-settlements"
    assert_select "form.stat-member-filter[action='#{home_section_path(section: "finance")}'] select[name=member_id]"
  end

  test "settlements show who owes whom, the same from both sides" do
    transfer!(payer: profiles(:bob), counterparty: @profile, date: Date.current - 1, cents: 4200)

    [ @profile, profiles(:bob) ].each do |viewer|
      sign_in viewer
      get home_report_path(section: "finance", name: "settlements")

      assert_select ".stat-table__row", text: /Carol.*Bob/m
    end
  end

  test "a member id the viewer can't reach falls back to everyone" do
    get home_section_path(section: "healthcare", member_id: profiles(:alice).id)

    assert_response :success
  end

  test "every page renders in Italian too" do
    @profile.update!(locale: "it")

    [ root_path, *SECTIONS.keys.map { |section| home_section_path(section: section) } ].each do |path|
      get path

      assert_response :success
      assert_select "body", text: /translation missing/i, count: 0
    end
  end

  test "an unknown page is not found" do
    get "#{Rails.configuration.x.mount_path}/home/secrets"

    assert_response :not_found
  end

  test "an unknown report of a page is not found" do
    get "#{Rails.configuration.x.mount_path}/home/agenda/reports/secrets"

    assert_response :not_found
  end

  test "needs attention shows six at a time with the whole count, pages in its own frame, and a page past the last is the last" do
    8.times { |n| task!(profile: @profile, date: Date.current - (n + 1), title: "Late #{n}") }

    get root_path
    assert_select ".stat-attention__count", "8"
    assert_select "turbo-frame#stat-attention-list .stat-attention__item", 6
    assert_select "turbo-frame#stat-attention-list a[data-turbo-frame='stat-attention-list'][data-turbo-action=advance][href*='attention_page=2']"
    assert_select ".stat-attention__more", 0
    assert_select "turbo-frame#stat-attention-list nav.pagination[aria-label=?]", "Pages of “Needs attention”"
    # Previous and next are an arrow and a word, the word dropped on a phone by the stylesheet
    assert_select "a.pagination__link--next i.pagination__arrow.fa-chevron-right"
    assert_select "a.pagination__link--next .pagination__word", "Next"
    assert_select "span.pagination__link--previous[aria-disabled=true] i.pagination__arrow.fa-chevron-left"

    get root_path(attention_page: 2), headers: { "Turbo-Frame" => "stat-attention-list" }
    assert_select "turbo-frame#stat-attention-list .stat-attention__item", 2

    get root_path(attention_page: 9)
    assert_select "turbo-frame#stat-attention-list .stat-attention__item", 2
  end

  test "the agenda's lists page ten rows at a time, each in its own frame" do
    12.times { |n| task!(profile: @profile, date: Date.current - (n + 1), title: "Late #{n}") }

    get home_section_path(section: "agenda", agenda_overdue_page: 2)

    assert_response :success
    assert_select "turbo-frame#home-agenda-overdue-page tbody tr", 2
    assert_select "turbo-frame#home-agenda-overdue-page a[href*='agenda_overdue_page=1']"
    assert_select ".home__more-rows", 0
  end

  test "the calendar keeps its own page" do
    get calendar_path

    assert_response :success
    assert_select ".calendar__grid"
  end
end
