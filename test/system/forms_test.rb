# frozen_string_literal: true

require "application_system_test_case"

# Every form opens and names its fields: each modal a route draws (a new
# record's form, an edit, a share), opened the way Turbo opens it and
# checked by axe. Generated from the routes, like the tenancy test,
# so a form is checked the day its route is drawn. (The admin's forms
# are the admin pages'.)
class FormsTest < ApplicationSystemTestCase
  include AlicesRecords

  # What a form needs beyond its route: what the new record is for.
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @day = Date.current
    build_alices_records
    sign_in @alice
  end

  test "every form opens and names its fields" do
    visit root_path

    problems = form_routes.flat_map do |route|
      controller = route.defaults[:controller]
      path = route.format(route.required_parts.to_h { |part| [ part, route_value(controller, part) ] })

      status = open_modal(path)
      next [ "#{path} answered #{status}" ] unless status == 200

      axe_violations(within: "#modals").map { "#{path}: #{_1}" }
    end

    assert_empty problems
  end

  # The day routes are one pair for every kind, so the route-driven test
  # opens one day's form; each kind draws its own, so every one is opened.
  test "every kind's day opens its form" do
    visit root_path

    problems = Event.types.flat_map do |kind|
      occurrence = @records.fetch("#{kind.model_name.route_key}#id")
      path = edit_event_day_path(occurrence.event, occurrence.date)

      status = open_modal(path)
      next [ "#{path} answered #{status}" ] unless status == 200

      axe_violations(within: "#modals").map { "#{path}: #{_1}" }
    end

    assert_empty problems
  end

  test "the purchase histories are pages, checked as every page is" do
    visit supply_purchases_path(@records.fetch("supplies#id"))
    assert_selector "h1.page-title"

    visit ingredient_purchases_path(@records.fetch("ingredients#id"))
    assert_selector "h1.page-title"
  end

  private

  def form_routes
    Rails.application.routes.routes.select do |route|
      controller, action = route.defaults.values_at(:controller, :action)
      route.verb == "GET" && action.to_s.start_with?("new", "edit") && !controller.to_s.start_with?("admin/", "assistant/evals", "profiles/")
    end
  end

  # Asks for the modal as Turbo does and lets Turbo put it on the page, in
  # place of the one before; the response's status.
  def open_modal(path)
    page.execute_script("document.getElementById('modals').replaceChildren()")
    status = using_wait_time(10) do # a request, not a lookup: longer than a lookup gets on a busy machine
      page.evaluate_async_script(<<~JS, path)
        const [url, done] = arguments;
        fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
          .then(response => response.text().then(html => { if (response.ok) Turbo.renderStreamMessage(html); done(response.status) }));
      JS
    end
    assert_selector "#modals > *" if status == 200
    status
  end
end
