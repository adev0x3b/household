# frozen_string_literal: true

require "test_helper"

class ReferenceRangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in profiles(:alice)
    @tsh = analytes(:tsh)
  end

  test "a new range: the form for its analyte in a modal, then back to the analyte's page with it listed" do
    get new_analyte_reference_range_path(@tsh), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", analyte_reference_ranges_path(@tsh) do
      assert_select "input[type=hidden][name='reference_range[analyte_id]']", false, "the analyte is the form's address, not a field of it"
      assert_select "select[name='reference_range[unit_id]'] option[value=?]", units(:miul).id.to_s
    end

    assert_difference -> { @tsh.reference_ranges.count }, 1 do
      post analyte_reference_ranges_path(@tsh), headers: submitted_from(analyte_path(@tsh)),
                                                params: { reference_range: { unit_id: units(:miul).id, sex: "any", low: "0.4", high: "4" } }
    end
    assert_redirected_to analyte_path(@tsh)
    follow_redirect!
    assert_toast "Reference range"
    assert_select ".reference-range-row__unit", text: units(:miul).name
  end

  test "a range corrected or deleted from the analyte's page comes back to it" do
    range = @tsh.reference_ranges.create!(unit: units(:miul), sex: :any, low: 0.4, high: 4)

    patch reference_range_path(range), params: { reference_range: { high: "4.5" } }, headers: submitted_from(analyte_path(@tsh))
    assert_redirected_to analyte_path(@tsh)
    assert_in_delta 4.5, range.reload.high

    delete reference_range_path(range), headers: submitted_from(analyte_path(@tsh))
    assert_redirected_to analyte_path(@tsh)
    assert_not ReferenceRange.exists?(range.id)
  end

  test "a second range for the same sex and unit stays on the form" do
    taken = reference_ranges(:glucose_any)

    assert_no_difference -> { ReferenceRange.count } do
      post analyte_reference_ranges_path(taken.analyte), params: { reference_range: { unit_id: taken.unit_id, sex: "any", high: "99" } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", analyte_reference_ranges_path(taken.analyte)
  end

  test "someone else's analyte is not found" do
    sign_in profiles(:bob)
    get root_path

    get new_analyte_reference_range_path(@tsh), as: :turbo_stream
    assert_response :not_found
  end
end
