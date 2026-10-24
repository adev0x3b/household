# frozen_string_literal: true

require "test_helper"

# What a person does in a browser, in headless Chrome (Selenium Manager
# finds it, or fetches Chrome for Testing) at a phone's size: the app is
# built for one first. Every page a test visits is checked by axe
# (Accessibility), and so is every state it asserts with assert_accessible.
# A test of what the keyboard alone can do presses keys (Keyboard).
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Devise::Test::IntegrationHelpers
  include Accessibility
  include Keyboard

  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  # Every request the browser makes is counted, for the teardown to wait on,
  # and a test may answer an address in the app's place (StandInAnswers).
  Capybara.app = StandInAnswers.new(InFlightRequests.new(Capybara.app))

  # Devise's sign_in waits for the next request the app sees, from any client
  # on any thread, and the browser sends some on its own, whenever it likes:
  # the service worker's (its script, re-read seconds after a page loads, and
  # the pages it caches) and Action Cable's. One of them arriving between a
  # test's sign_in and its first visit, from the page of the test before,
  # would take the sign-in, and the visit meet the sign-in page. Like the
  # assets, they are public, never the request a test signs in with.
  Warden.asset_paths << %r{\A/(service-worker\.js|manifest\.webmanifest|offline/[a-z]+|cable)\z}

  # A button that is an icon is named by its aria-label: tests find it the
  # way a screen reader does.
  Capybara.enable_aria_label = true

  # What a test waits for to show up (a live message, a card after a save):
  # Capybara's 2s are short on a CI machine running a browser per worker.
  Capybara.default_max_wait_time = 5

  def visit(...)
    park_pointer
    super.tap do
      wait_for_controllers
      assert_accessible
    end
  end

  # After every visit, turbo-rails waits for each live stream on the page to
  # be confirmed, as long as Capybara waits for anything. A browser a test
  # has only just started (a second person's, in using_session) loads every
  # script before it connects, and Action Cable tries a refused connection
  # again only seconds later: on a busy CI machine, together more than
  # Capybara's five.
  def connect_turbo_cable_stream_sources(...)
    using_wait_time(15) { super }
  end

  # Inside a day's card on the calendar page.
  def within_day(date, &)
    within("#day_#{date.iso8601}", &)
  end

  # Opens the form for a new series of `kind` (:task, :medication…) from
  # the "+" on a day's card, through the page's one menu of the kinds.
  def add_to_day(date, kind)
    within_day(date) { click_on I18n.t("calendar.day_card.add_event_on", date: I18n.l(date, format: :day_long)) }
    within("#day_add_menu") { click_on I18n.t("calendar.day_card.event_types.#{kind}") }
    assert_selector ".modal"
  end

  # A page hears its live updates only once Action Cable has confirmed its
  # subscriptions, a moment after it loads; a broadcast sent before then is
  # lost. Turbo marks each stream source "connected" when its subscription
  # is confirmed, so a test that expects a push waits for every one of them.
  def assert_listening
    sources = all("turbo-cable-stream-source", visible: :all, minimum: 1).size
    assert_selector "turbo-cable-stream-source[connected]", visible: :all, count: sources
  end

  # A page that is left may still have a request being answered, and closes
  # its Action Cable connection a moment later, on Action Cable's own threads,
  # where what a channel does then writes to the database (CalendarChannel's
  # unsubscribe; its periodic refresh until then). All of it ends before the
  # next test begins: a request that ran on into this transaction's teardown
  # would read and write the next test's rows, and the channel's writes
  # crashed a CI worker inside the pg gem.
  def after_teardown
    Capybara.reset_sessions!
    InFlightRequests.wait_until_idle
    wait_for_cable_to_close
  ensure
    super
  end

  private

  # The browser is kept from one test to the next, and so is where its
  # pointer was left. A page drawn under it is hovered, and Turbo prefetches
  # a hovered link: a test's first page could fetch the next one before the
  # test had said what it should answer (StandInAnswers). Every visit starts
  # with the pointer in the corner of the top bar, where there is no link.
  def park_pointer
    page.driver.browser.action.move_to_location(0, 0).perform
  end

  # Stimulus registers each controller once its module has loaded, a moment
  # after the page itself, and a press that lands before then does nothing
  # (an "Add" in a modal opened at once adds no row). A visit is done
  # when every controller the import map names is registered, so whatever
  # the page opens after it is wired up as it appears. A page drawn without
  # the app's scripts (a public error page) has none to wait for.
  def wait_for_controllers
    assert_eventually("Stimulus never registered every controller", within: Capybara.default_max_wait_time) do
      evaluate_script(<<~'JS')
        (() => {
          const importmap = document.querySelector("script[type=importmap]")
          if (!importmap) return true

          const controllers = Object.keys(JSON.parse(importmap.text).imports).filter((path) => /^controllers\/.*_controller$/.test(path))
          return window.Stimulus?.router.modules.length === controllers.length
        })()
      JS
    end
  end

  # A browser that hung keeps its connection: Action Cable is restarted
  # rather than waited on.
  def wait_for_cable_to_close(within: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    sleep 0.01 until ActionCable.server.connections.empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    ActionCable.server.restart if ActionCable.server.connections.any?
  end
end
