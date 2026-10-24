# frozen_string_literal: true

require "test_helper"

# An appointment is a visit to a doctor (Healthcare) or anything else one
# goes to — an interview, dinner with friends (Agenda): its kind decides
# the section, the icon and the word for who it's with.
class AppointmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
    @day = Date.new(2026, 10, 6)
  end

  def create(kind:, counterpart:, title: "Meeting", **extra)
    post appointments_path, as: :turbo_stream, params: {
      appointment: { title: title, date: @day.iso8601, start_time: "11:00", location: "Via Roma 1",
                     details_attributes: { kind: kind, counterpart: counterpart } }
    }.deep_merge(extra)
    Appointment.find_by!(title: title)
  end

  test "a new appointment's form offers every kind, each with its word for who it's with" do
    get new_appointment_path(date: @day.iso8601), as: :turbo_stream

    assert_response :success
    assert_select "form[data-controller~=appointment-form]"
    assert_select "select[name='appointment[details_attributes][kind]'][data-appointment-form-target=kind]" do
      assert_select "option", Appointment::Kind::ALL.size
      assert_select "option[selected][value=medical][data-label=Provider]"
      assert_select "option[value=work][data-label=With][data-placeholder=?]", "Company or person"
      assert_select "option[value=work][data-title-placeholder=?][data-location-placeholder=?]", "e.g. Job interview", "Address or video call link"
    end
    assert_select "input[name='appointment[title]'][data-appointment-form-target=titleInput][placeholder=?]", "e.g. Endocrinologist follow-up"
    assert_select "input[name='appointment[location]'][data-appointment-form-target=locationInput][placeholder=?]", "Address or clinic"
    assert_select "label[data-appointment-form-target=counterpartLabel]", text: "Provider"
    assert_select "input[name='appointment[details_attributes][counterpart]'][placeholder=?]", "Doctor or clinic name"
    assert_select "input[name='appointment[start_time]']"
    assert_select "input[name='transaction[amount]']"
  end

  test "a fee without a payment method brings the form back asking for one, the visit unsaved" do
    assert_no_difference -> { Appointment.count } do
      post appointments_path, as: :turbo_stream, params: {
        appointment: { title: "Dentist", date: @day.iso8601, details_attributes: { kind: "medical", counterpart: "Dr. Rossi" } },
        transaction: { amount: "60", payment_method: "" }
      }
    end

    assert_response :unprocessable_content
    assert_form_error "Payment method can't be blank"
  end

  test "a visit to the doctor is Healthcare, with its provider" do
    visit = create(kind: "medical", counterpart: "Dr. Moretti", title: "Endocrinologist")

    assert_equal "medical", visit.details.kind
    assert_equal "Dr. Moretti", visit.counterpart
    assert_equal :healthcare, visit.section
    assert_equal "11:00", visit.start_time.strftime("%H:%M")
    assert_equal "Via Roma 1", visit.location
    assert_includes Event.in_section(:healthcare), visit
  end

  test "an interview is Agenda, with whoever it's with" do
    interview = create(kind: "work", counterpart: "ACME", title: "Interview")

    assert_equal :agenda, interview.section
    assert_equal "ACME", interview.counterpart
    assert_includes Event.in_section(:agenda), interview
    assert_not_includes Event.in_section(:healthcare), interview
  end

  test "editing a work appointment words who it's with as With, and its form is Agenda's" do
    interview = create(kind: "work", counterpart: "ACME", title: "Interview")

    get edit_event_day_path(interview, interview.starts_on), as: :turbo_stream

    assert_select ".modal__dialog.section--agenda"
    assert_select "label[data-appointment-form-target=counterpartLabel]", text: "With"
    assert_select "input[name='appointment[details_attributes][counterpart]'][value=ACME]"
    assert_select "input[name='appointment[title]'][placeholder=?]", "e.g. Job interview"
  end

  test "the collection picker is worded by the appointment's section" do
    therapy = collections(:b12) # Alice's B12, Healthcare
    job_hunt = Collection.create!(profile: @alice, name: "Job hunt", section: "agenda")
    visit = appointment!(profile: @alice, date: @day, kind: :medical, title: "Checkup")
    interview = appointment!(profile: @alice, date: @day, kind: :work, title: "Interview")

    get edit_event_day_path(visit.event, visit.date), as: :turbo_stream
    assert_select "label[for=event_collection_id]", text: "Therapy"
    assert_select "select[name='event[collection_id]'] option[value=?]", therapy.id.to_s
    assert_select "select[name='event[collection_id]'] option[value=?]", job_hunt.id.to_s, 0

    get edit_event_day_path(interview.event, interview.date), as: :turbo_stream
    assert_select "label[for=event_collection_id]", text: "Collection"
    assert_select "select[name='event[collection_id]'] option[value=?]", job_hunt.id.to_s
    assert_select "select[name='event[collection_id]'] option[value=?]", therapy.id.to_s, 0
  end

  test "a new visit goes in the therapy picked, never in one the person can't reach" do
    visit = create(kind: "medical", counterpart: "Dr. Moretti", title: "In therapy", event: { frequency: "none", collection_id: collections(:b12).id })
    assert_equal collections(:b12), visit.collection

    other = create(kind: "medical", counterpart: "Dr. Moretti", title: "Not mine", event: { frequency: "none", collection_id: collections(:fibromyalgia).id })
    assert_nil other.collection
  end

  test "changing the kind of a one-off moves it to its new section" do
    visit = appointment!(profile: @alice, date: @day, kind: :medical, counterpart: "Dr. Moretti", title: "Lunch")

    patch event_day_path(visit.event, visit.date), as: :turbo_stream, params: {
      appointment: { title: "Lunch", details_attributes: { kind: "social", counterpart: "Sam" } },
      event: { frequency: "none" }
    }

    assert_response :success
    event = visit.event.reload
    assert_equal :agenda, event.section
    assert_equal "Sam", event.counterpart
  end

  test "its fee is filed under the kind's category and named after who it was with" do
    create(kind: "social", counterpart: "Friends", title: "Concert", transaction: { amount: "35", payment_method: "card" })

    day = Appointment.find_by!(title: "Concert").first_occurrence
    fee = day.costs.sole
    assert_equal "entertainment", fee.details.category
    assert_equal BigDecimal("35"), fee.details.amount
    assert_equal "Friends", fee.details.counterparty
  end
end
