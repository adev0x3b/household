# frozen_string_literal: true

require "test_helper"

class AnalytesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in profiles(:alice)
  end

  test "index renders the navbar search and the results frame" do
    get analytes_path

    assert_response :success
    assert_includes response.body, 'type="search"'
    assert_includes response.body, %(id="#{Views::Analytes::List::FRAME_ID}")
  end

  test "search answers the results frame only, never the search input" do
    get analytes_path(q: "gluc"), headers: { "Turbo-Frame" => Views::Analytes::List::FRAME_ID }

    assert_response :success
    assert_includes response.body, %(id="#{Views::Analytes::List::FRAME_ID}")
    assert_includes response.body, "Glucose"
    assert_not_includes response.body, "Cholesterol"
    assert_not_includes response.body, 'type="search"'
  end

  test "a new analyte: the form in a modal, then the card on the list" do
    get new_analyte_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='analyte[name]']", analytes_path

    assert_difference -> { profiles(:alice).analytes.count }, 1 do
      post analytes_path, params: { analyte: { name: "Ferritin" } }, headers: submitted_from(analytes_path)
    end
    assert_redirected_to analytes_path
    follow_redirect!
    assert_select ".analyte-card__name", text: "Ferritin"
    assert_toast "Analyte added"
  end

  test "a name it has already, in any case, stays on the form" do
    assert_no_difference -> { Analyte.count } do
      post analytes_path, params: { analyte: { name: "glucose" } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", analytes_path
    assert_form_error "Name has already been taken"
  end

  test "an analyte goes with its ranges, but not while results use it" do
    assert_no_difference -> { Analyte.count } do
      delete analyte_path(analytes(:glucose)), as: :turbo_stream
    end
    assert_toast "Glucose can't be deleted while lab results use it."

    ranged = analytes(:tsh)
    ranged.reference_ranges.create!(unit: units(:miul), sex: :any, low: 0.4, high: 4)
    delete analyte_path(ranged), headers: submitted_from(analyte_path(ranged))
    assert_redirected_to analytes_path
    assert_not Analyte.exists?(ranged.id)
    assert_empty ReferenceRange.where(analyte_id: ranged.id)
    follow_redirect!
    assert_toast "Analyte deleted."
  end
end
