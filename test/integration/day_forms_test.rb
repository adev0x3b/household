# frozen_string_literal: true

require "test_helper"

# What every kind's form and days do the same way (SeriesController,
# DaysController, DayCompletionsController), asked of each kind the app
# has: a new kind is tested the day it is added.
class DayFormsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @day = Date.new(2026, 10, 5)
    sign_in @alice
  end

  Event.types.each do |kind|
    test "#{kind.name}: a new one opens its form for the day asked" do
      get new_polymorphic_path(kind, date: "2026-10-06"), as: :turbo_stream

      assert_select "turbo-stream[action=update][target=modals] form[action=?]", polymorphic_path(kind)
      assert_select "input[type=hidden][name='#{kind.model_name.param_key}[date]'][value='2026-10-06']"
    end

    test "#{kind.name}: its form asks in the order every kind's does" do
      day = day!(weekly_event(profile: @alice, type: kind, starts_on: @day), date: @day)
      key = kind.model_name.param_key
      order = [ "#{key}[apply_to]", "#{key}[title]", "#{key}[notes]", "event[frequency]", "event[collection_id]", "transaction[amount]", "#{key}[status]" ]

      get edit_event_day_path(day.event, day.date), as: :turbo_stream
      assert_select "form[action=?]", event_day_path(day.event, day.date)

      names = css_select("form [name]").map { _1["name"] }
      asked = order.select { names.include?(_1) }
      assert_equal [ "#{key}[apply_to]", "#{key}[notes]" ], asked & [ "#{key}[apply_to]", "#{key}[notes]" ], "every kind asks which days and takes notes"
      assert_equal(asked, asked.sort_by { names.index(_1) })
    end

    test "#{kind.name}: ticking a day nothing is stored about saves it done, once" do
      event = weekly_event(profile: @alice, type: kind, starts_on: @day)
      tick = -> { post event_day_completion_path(event, @day + 7), as: :turbo_stream }

      assert_difference -> { event.occurrences.count }, 1 do
        tick.call
        tick.call
      end
      assert_predicate event.occurrence_on(@day + 7), :completed?
      assert_toast I18n.t("#{kind.model_name.route_key}.notices.completed")
    end

    test "#{kind.name}: a saved day is done or not as the press says, however often it comes" do
      day = day!(weekly_event(profile: @alice, type: kind, starts_on: @day), date: @day)

      2.times { post event_day_completion_path(day.event, day.date), as: :turbo_stream }
      assert_predicate day.reload, :completed?
      assert_toast I18n.t("#{kind.model_name.route_key}.notices.completed")

      2.times { delete event_day_completion_path(day.event, day.date), as: :turbo_stream }
      assert_predicate day.reload, :pending?
      assert_toast I18n.t("#{kind.model_name.route_key}.notices.uncompleted")
    end
  end
end
