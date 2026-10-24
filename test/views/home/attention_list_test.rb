# frozen_string_literal: true

require "test_helper"

# "Needs attention": each item worded and drawn for its kind, opening its day.
class Views::Home::AttentionListTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @date = Date.new(2026, 10, 2)
  end

  test "a meal not marked and a lab test pending say so; an appointment shows its own kind's icon" do
    items = [
      item(:unrecorded_meal, meal_on(@profile, @date, title: "Lasagna")),
      item(:pending_lab_result, lab_result!(profile: @profile, date: @date, title: "Blood panel")),
      item(:appointment_outcome, appointment!(profile: @profile, date: @date, title: "Dinner", kind: :social)),
      item(:appointment_outcome, appointment!(profile: @profile, date: @date, title: "Dentist", kind: :medical))
    ]

    rows = parse(Views::Home::AttentionList.new(items: items)).css(".stat-attention__item").map do |row|
      [ row.at_css("strong").text, row.at_css(".stat-attention__detail").text, row.at_css(".stat-attention__icon")["class"][/fa-[a-z-]+(?= stat)/] ]
    end

    assert_equal [
      [ "Lasagna", "Planned for October 2, 2026, not marked as eaten", "fa-utensils" ],
      [ "Blood panel", "Was on October 2, 2026. Record the values", "fa-vial" ],
      [ "Dinner", "Was on October 2, 2026. Record how it went", "fa-user-group" ],
      [ "Dentist", "Was on October 2, 2026. Record how it went", "fa-user-doctor" ]
    ], rows
  end

  test "a series with several days in that state says how many, beside its newest" do
    dose = medication!(profile: @profile, date: @date, name: "Metformin")
    rows = parse(Views::Home::AttentionList.new(items: [ item(:missed_dose, dose, count: 6), item(:overdue_task, task!(profile: @profile, date: @date), count: 1) ]))

    assert_equal([ "6 times", nil ], rows.css(".stat-attention__item").map { _1.at_css(".stat-attention__times")&.text })
  end

  test "a supply running out opens a new purchase, an expired batch its own purchase, each in place" do
    purchase = supply_purchase!(profile: @profile, name: "Insulin pens")
    supply = purchase.supply
    items = [
      Reports::AttentionItem.new(kind: :supply_running_out, severity: :critical, subject: supply, date: @date, opens: supply, words: { count: 1 }),
      Reports::AttentionItem.new(kind: :supply_low_stock, severity: :critical, subject: supply, date: nil, opens: supply),
      Reports::AttentionItem.new(kind: :batch_expired, severity: :critical, subject: supply, date: @date, opens: purchase)
    ]

    rows = parse(Views::Home::AttentionList.new(items: items)).css(".stat-attention__item").map do |row|
      [ row.at_css(".stat-attention__detail").text, row.at_css("a")["href"], row.at_css("a").key?("data-turbo-stream") ]
    end

    assert_equal [
      [ "Runs out in 1 day", "/supplies/#{supply.id}/purchases/new", true ],
      [ "Below the low-stock threshold", "/supplies/#{supply.id}/purchases/new", true ],
      [ "A batch expired on October 2, 2026 and still has stock", "/supply_purchases/#{purchase.id}/edit", true ]
    ], rows
  end

  test "a day that passed unrecorded can be settled by whoever may change it; a supply, or a day only to be asked about, cannot" do
    task = task!(profile: @profile, date: @date, title: "Laundry")
    supply = supply_purchase!(profile: @profile, name: "Insulin pens").supply
    items = [
      item(:overdue_task, task, resolvable: true),
      Reports::AttentionItem.new(kind: :supply_low_stock, severity: :critical, subject: supply, date: nil, opens: supply)
    ]

    html = parse(Views::Home::AttentionList.new(items: items, viewer: @profile, list: { section: :agenda }))
    labels = html.css(".stat-attention__item").map { _1.at_css(".stat-attention__resolve button")&.[]("aria-label") }
    assert_equal [ "Mark Laundry as skipped", nil ], labels
    assert_equal task.event_id.to_s, html.at_css(".stat-attention__resolve input[name=event_id]")["value"]
    assert_match %r{/home/agenda/attention/resolutions\z}, html.at_css(".stat-attention__footer form")["action"]

    nobody = parse(Views::Home::AttentionList.new(items: items))
    assert_empty nobody.css(".stat-attention__resolve, .stat-attention__footer")
    outsider = parse(Views::Home::AttentionList.new(items: items, viewer: profiles(:alice)))
    assert_empty outsider.css(".stat-attention__resolve, .stat-attention__footer")
  end

  test "a settled row's button names where the focus goes: the next row's, else the one before, else the heading" do
    days = [ "Laundry", "Dishes", "Bins" ].map { |title| task!(profile: @profile, date: @date, title: title) }
    items = days.map { |day| item(:overdue_task, day, resolvable: true) }

    buttons = parse(Views::Home::AttentionList.new(items: items, viewer: @profile)).css(".stat-attention__resolve button")
    ids = days.map { "attention-overdue-task-#{_1.event_id}-resolve" }

    assert_equal(ids, buttons.map { _1["id"] })
    assert_equal([ "#{ids[1]} stat-attention-heading", "#{ids[2]} #{ids[0]} stat-attention-heading", "#{ids[1]} stat-attention-heading" ],
                 buttons.map { _1["data-focus-fallback"] })
  end

  private

  def item(kind, day, count: 1, resolvable: false)
    Reports::AttentionItem.new(kind: kind, severity: :warning, subject: day.event_label, date: day.date, occurrence: day, count: count, resolvable: resolvable)
  end

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
end
