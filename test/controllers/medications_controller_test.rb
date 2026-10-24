# frozen_string_literal: true

require "test_helper"

class MedicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = profiles(:bob)
    sign_in @profile
    @needles = supply_purchase!(profile: @profile, name: "Needles", quantity: 100).supply
  end

  teardown { travel_back }

  def stock = SupplyPurchase.where(profile: @profile, supply: @needles).sum(:quantity_remaining)

  # Weekly on Thursdays from 2026-09-17, in the left thigh first; each dose uses a needle.
  def injections
    @injections ||= series!("Medication", profile: @profile, starts_on: Date.new(2026, 9, 17), title: "Cobalamin", rrule: "FREQ=WEEKLY",
                                          kind: :injection, area: :thigh, side: :left).tap do |event|
      event.details.supply_uses.create!(supply: @needles, quantity: 1)
    end
  end

  def dose_fields(dose, **overrides)
    { title: dose.title, details_attributes: { kind: dose.details.kind, area: dose.details.area, side: dose.details.side } }.merge(overrides)
  end

  test "cancelling a taken dose in the form gives its supplies back" do
    dose = injections.occurrence_on(Date.new(2026, 9, 24)).complete!
    assert_equal 99, stock

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: {
      medication: dose_fields(dose, status: "cancelled"), event: { frequency: "weekly", interval: 1 }
    }

    assert_response :success
    assert_equal "cancelled", dose.reload.status
    assert_equal 100, stock, "the needle went back into stock"
  end

  test "a projected injection opens on the side it alternates to" do
    get edit_event_day_path(injections, "2026-09-24"), as: :turbo_stream

    assert_response :success
    assert_select "select[name='medication[details_attributes][side]'] option[selected][value=right]"
    assert_select "select[name='medication[details_attributes][area]'] option[selected][value=thigh]"
  end

  test "what a dose uses: this day's own list, or the whole series'" do
    dose = injections.occurrence_on(Date.new(2026, 9, 24)).materialize!
    use = injections.details.supply_uses.sole
    key = "medication[details_attributes][supply_uses_attributes]"

    get edit_event_day_path(injections, dose.date), as: :turbo_stream
    assert_select "select[name='#{key}[#{use.id}][supply_id]'] option[selected][value=?]", @needles.id.to_s
    assert_select "input[name='#{key}[#{use.id}][id]'][value=?][data-apply-to-scope=series][disabled]", use.id.to_s

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: {
      medication: dose_fields(dose, apply_to: "day", details_attributes: dose_fields(dose)[:details_attributes].merge(
        supply_uses_attributes: { use.id.to_s => { supply_id: @needles.id, quantity: "2", _destroy: "false" } }
      )),
      event: { frequency: "weekly", interval: 1 }
    }
    assert_equal([ [ @needles.id, BigDecimal("2") ] ], dose.reload.details.resolved_uses.map { [ _1.supply_id, _1.quantity ] })
    assert_equal [ BigDecimal("1") ], injections.details.reload.supply_uses.map(&:quantity), "the other doses keep using one"

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: {
      medication: dose_fields(dose, apply_to: "series", details_attributes: dose_fields(dose)[:details_attributes].merge(
        supply_uses_attributes: { use.id.to_s => { id: use.id, supply_id: @needles.id, quantity: "3", _destroy: "false" } }
      )),
      event: { frequency: "weekly", interval: 1 }
    }
    assert_equal [ BigDecimal("3") ], injections.details.reload.supply_uses.map(&:quantity)
  end

  # Every request is watched for N+1 queries (test_helper.rb): a dose's
  # supplies are planned, checked and drawn together, however many it uses.
  test "a dose planned with several supplies draws from each when taken" do
    swabs = supply_purchase!(profile: @profile, name: "Swabs", quantity: 50).supply
    vials = supply_purchase!(profile: @profile, name: "Vials", quantity: 10).supply
    uses = [ [ @needles, "1" ], [ swabs, "2" ], [ vials, "1" ] ].each_with_index.to_h { |(supply, quantity), i| [ i.to_s, { supply_id: supply.id, quantity: quantity } ] }

    post medications_path, as: :turbo_stream, params: {
      medication: { title: "B12", date: "2026-09-24", details_attributes: { kind: "pill", supply_uses_attributes: uses } },
      event: { frequency: "weekly", interval: 1 }
    }
    series = Medication.find_by!(title: "B12")
    assert_equal [ @needles, swabs, vials ].map(&:id).sort, series.details.supply_uses.map(&:supply_id).sort

    dose = series.occurrence_on(Date.new(2026, 9, 24)).materialize!
    post event_day_completion_path(series, dose.date), as: :turbo_stream
    assert_equal([ 99, 48, 9 ], [ @needles, swabs, vials ].map { SupplyPurchase.where(supply: _1).sum(:quantity_remaining).to_i })
  end

  # --- Several doses a day ---------------------------------------------------

  def twice_daily = @twice_daily ||= timed_medication!(profile: @profile, starts_on: Date.new(2026, 9, 20), times: %w[CM 20:00])

  test "taking one dose of the day from the calendar saves that dose alone" do
    event = twice_daily.event
    day = Date.new(2026, 9, 24)

    post event_day_completion_path(event, day, time: "20:00"), as: :turbo_stream

    assert_response :success
    doses = event.occurrences.where(date: day)
    assert_equal [ "20:00" ], doses.map(&:time_string)
    assert_predicate doses.sole, :completed?
    assert_nil doses.sole.anchor

    post event_day_completion_path(event, day, time: "08:00"), as: :turbo_stream
    assert_equal "CM", event.occurrence_on(day, time: "08:00").anchor
    assert_equal 2, event.occurrences.where(date: day).count
  end

  test "the form opens the dose asked for and a new series gets its times" do
    get edit_event_day_path(twice_daily.event, "2026-09-25", time: "20:00"), as: :turbo_stream
    assert_response :success
    assert_select "form[action=?]", event_day_path(twice_daily.event, "2026-09-25", time: "20:00")
    assert_select "input[type=hidden][name='medication[time]']", 0, "the day is the form's address, not a field of it"
    assert_select ".dose-times__row", count: 3, message: "two rows and the template's"

    post medications_path, as: :turbo_stream, params: {
      medication: { title: "Amoxicillin", date: "2026-09-24", details_attributes: { kind: "pill" } },
      event: { frequency: "daily", interval: 1, slots_submitted: "1", slots: [ "08:00", "14:00", "20:00" ] }
    }

    assert_response :success
    event = Medication.find_by!(title: "Amoxicillin")
    assert_equal [ [ "08:00", nil ], [ "14:00", nil ], [ "20:00", nil ] ], event.slots
    assert_equal "08:00", event.first_occurrence.time_string
  end

  test "a new series that fails to save comes back with the times the form sent" do
    post medications_path, as: :turbo_stream, params: {
      medication: { title: "", date: "2026-09-24", details_attributes: { kind: "pill" } },
      event: { frequency: "daily", interval: 1, slots_submitted: "1", slots: [ "CM", "20:00" ] }
    }

    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] .dose-times__row", count: 3, message: "two rows and the template's"
    assert_select "input[name='event[slots][]'][value=CM]"
    assert_select "input[name='event[slots][]'][value='20:00']"
  end

  test "a new series that fails to save comes back with its repeat and its collection" do
    post medications_path, as: :turbo_stream, params: {
      medication: { title: "", date: "2026-09-24", details_attributes: { kind: "pill" } },
      event: { frequency: "weekly", interval: 2, week_days: [ "monday" ], collection_id: collections(:b12).id }
    }

    assert_select "select[name='event[frequency]'] option[selected][value=weekly]"
    assert_select "select[name='event[collection_id]'] option[selected][value=?]", collections(:b12).id.to_s
  end

  test "an end that isn't a date is the form's error, and nothing is saved" do
    assert_no_difference -> { Event.count } do
      post medications_path, as: :turbo_stream, params: {
        medication: { title: "Amoxicillin", date: "2026-09-24", details_attributes: { kind: "pill" } },
        event: { frequency: "daily", interval: 1, ends: "next Tuesday" }
      }
    end

    assert_form_error "Repeats is invalid"
  end

  test "a new injection without its side marks the side, though the form was rebuilt from what was sent" do
    post medications_path, as: :turbo_stream, params: {
      medication: { title: "B12", date: "2026-09-24", details_attributes: { kind: "injection", area: "thigh" } },
      event: { frequency: "weekly", interval: 1 }
    }

    assert_response :unprocessable_content
    assert_form_error "Side can't be blank"
    assert_select ".field.is-invalid select#medication_details_attributes_side[aria-invalid=true]"
    assert_select "#medication_details_attributes_side_error", text: "Side can't be blank"
  end

  test "editing a dose keeps the series' times unless the form carried them; then the series goes on without them from today" do
    dose = twice_daily
    fields = { title: "Metformin 500", apply_to: "series", details_attributes: { kind: "pill" } }

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields, event: { frequency: "daily", interval: 1 } }
    assert_equal [ [ "08:00", "CM" ], [ "20:00", nil ] ], dose.event.reload.slots
    assert_equal "Metformin 500", dose.event.title

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields, event: { frequency: "daily", interval: 1, slots_submitted: "1" } }
    assert_predicate dose.event.reload, :timed?, "the doses behind keep their times"
    assert_not Medication.where(title: "Metformin 500").where.not(id: dose.event.id).sole.timed?
  end

  test "a skipped dose keeps why, and loses it when taken; a taken one keeps when, on the person's clock" do
    @profile.update!(time_zone: "Europe/Rome")
    dose = twice_daily
    fields = { title: dose.title, details_attributes: { kind: "pill" } }

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields.merge(status: "skipped", skipped_reason: "forgot") }
    assert_equal "skipped", dose.reload.status
    assert_equal "forgot", dose.skipped_reason

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields.merge(status: "skipped", skipped_reason: "refused") }
    assert_equal "refused", dose.reload.skipped_reason

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields.merge(status: "completed", completed_at: "2026-09-24T19:40") }
    assert_predicate dose.reload, :completed?
    assert_nil dose.skipped_reason
    assert_equal Time.utc(2026, 9, 24, 17, 40), dose.completed_at

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields.merge(status: "completed", completed_at: "2026-09-24T20:05") }
    assert_equal Time.utc(2026, 9, 24, 18, 5), dose.reload.completed_at

    patch event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream, params: { medication: fields.merge(status: "completed") }
    assert_equal Time.utc(2026, 9, 24, 18, 5), dose.reload.completed_at, "nothing said: unchanged"

    get edit_event_day_path(dose.event, dose.date, time: dose.time_string), as: :turbo_stream
    assert_select "input[name='medication[completed_at]'][value='2026-09-24T20:05']"
    assert_select "select[name='medication[skipped_reason]'] option[value=forgot]", text: "Forgot"
  end
end
