# frozen_string_literal: true

require "test_helper"

# Someone who reads the app in Italian writes one and a half as 1,5. A
# number field sends a point whatever the language, and must be given one:
# the browser leaves it empty when its value has a comma. The forms that read
# a typed number as text read the comma too.
class NumbersInItalianTest < ActionDispatch::IntegrationTest
  include AlicesRecords

  NUMBER = /\A-?\d*(\.\d+)?\z/

  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @day = Date.current
    build_alices_records
    @alice.update!(locale: "it")
    sign_in @alice
  end

  test "every form shows its numbers with a decimal point" do
    give_every_decimal_a_fraction
    shown = []

    problems = form_paths.flat_map do |path|
      get path, as: :turbo_stream
      next [ "#{path} answered #{response.status}" ] unless response.successful?

      css_select("input[type=number][value]").filter_map do |input|
        shown << input["value"]
        "#{path}: #{input["name"]} shows #{input["value"]}" unless input["value"].match?(NUMBER)
      end
    end

    assert_empty problems
    assert shown.any? { _1.include?(".") }, "some form showed a fraction"
  end

  test "a grocery line and a lab value typed with a decimal comma are read as one" do
    list = @records.fetch("grocery_lists#id")
    post grocery_list_grocery_list_items_path(list), params: { grocery_list_item: { text: "1,5 l latte" } }, as: :turbo_stream
    milk = list.grocery_list_items.joins(:ingredient).find_by!(ingredients: { name: "latte" })
    assert_equal [ 1.5, "l" ], [ milk.quantity, milk.unit.name ]

    report = @records.fetch("lab_test_results#id")
    patch event_day_path(report.event, report.date), as: :turbo_stream, params: {
      lab_test_result: { title: report.title, lab_test_result_entries_attributes: { "-1" => { analyte_name: "Glucose", value: "312,5", unit_name: "mg/dL" } } },
      event: { frequency: "none" }
    }
    assert_in_delta 312.5, report.lab_test_result_entries.reload.sole.numeric_value
  end

  private

  # Every new and edit form a route draws, and each kind's day form.
  def form_paths
    routes = Rails.application.routes.routes.select do |route|
      controller, action = route.defaults.values_at(:controller, :action).map(&:to_s)
      route.verb == "GET" && action.start_with?("new", "edit") && !controller.start_with?("admin/", "assistant/evals", "profiles/")
    end
    days = Event.types.map { |kind| @records.fetch("#{kind.model_name.route_key}#id") }

    routes.map { |route| route.format(route.required_parts.to_h { [ _1, route_value(route.defaults[:controller], _1) ] }) } +
      days.map { |day| edit_event_day_path(day.event, day.date) }
  end

  # A half more in every decimal Alice's records and their series' details
  # hold, so each form has a fraction to show, its bounds still in order.
  def give_every_decimal_a_fraction
    records = @records.values.grep(ActiveRecord::Base).uniq
    records += records.filter_map { _1.event.details if _1.is_a?(Occurrence) }
    records.each do |record|
      decimals = record.class.columns.select { _1.type == :decimal }.filter_map { |column| [ column.name, record[column.name] + 0.5 ] if record[column.name] }
      record.update_columns(decimals.to_h) if decimals.any?
    end
  end
end
