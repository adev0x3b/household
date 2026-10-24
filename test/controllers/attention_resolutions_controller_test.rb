# frozen_string_literal: true

require "test_helper"

# "Needs attention" settled from its list: one series, or the whole list of
# the page the press was on; the page is drawn again in place.
class AttentionResolutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @carol = profiles(:carol)
    sign_in @carol
    @today = Date.current
  end

  test "one series' days still to do are marked skipped, and the page comes back without them" do
    late = task!(profile: @carol, date: @today - 1, title: "Pay the rent")
    other = task!(profile: @carol, date: @today - 3, title: "Call the plumber")

    post attention_resolutions_path, params: { event_id: late.event_id }, headers: submitted_from(root_path)

    assert_redirected_to root_path
    assert_equal "skipped", late.reload.status
    assert_equal "pending", other.reload.status
    follow_redirect!
    assert_toast "Marked as skipped."
    assert_select ".stat-attention__item", text: /Pay the rent/, count: 0
    assert_select ".stat-attention__item", text: /Call the plumber/, count: 1
  end

  test "the overview's whole list, and a section page's for its member" do
    late = task!(profile: @carol, date: @today - 1)
    missed = medication!(profile: @carol, date: @today - 2)

    post attention_resolutions_path(section: "healthcare"), headers: submitted_from(home_section_path(section: "healthcare"))
    assert_redirected_to home_section_path(section: "healthcare")
    assert_equal "skipped", missed.reload.status
    assert_equal "pending", late.reload.status, "the agenda's item is not on the healthcare page"

    post attention_resolutions_path, headers: submitted_from(root_path)
    assert_redirected_to root_path
    assert_equal "skipped", late.reload.status
    follow_redirect!
    assert_toast "Marked everything as skipped."
  end

  test "a press with nothing left to settle is refused where it was made, and a section no page has is not found" do
    done = task!(profile: @carol, date: @today - 1, status: :completed)

    post attention_resolutions_path, params: { event_id: done.event_id }, headers: submitted_from(root_path)
    assert_response :unprocessable_content
    assert_toast "Nothing left here to mark as skipped."

    post attention_resolutions_path(section: "secrets")
    assert_response :not_found
  end

  test "the list offers the press only on what the viewer may settle outright" do
    bob = profiles(:bob)
    link!(@carol, bob)
    grant(@carol, bob, "Task", write: :on)
    grant(@carol, bob, "Meal", write: :ask)
    task = task!(profile: @carol, date: @today - 1, title: "Pay the rent")
    meal_on(@carol, @today - 2, title: "Lasagna")
    sign_in bob

    get root_path

    assert_select ".stat-attention__item", text: /Lasagna/ do
      assert_select "form", 0, "a day bob may only ask about has no press"
    end
    assert_select "form.stat-attention__resolve[action='#{attention_resolutions_path}'][data-turbo-frame=_top] input[name=event_id][value='#{task.event_id}']"
    assert_select "form.stat-attention__resolve button[aria-label='Mark Pay the rent as skipped']"
    assert_select ".stat-attention__footer form[data-turbo-frame=_top][data-turbo-confirm] button.stat-attention__resolve-all", text: "Mark all as skipped"

    sign_in @carol
    get home_section_path(section: "agenda", member_id: @carol.id)
    assert_select ".stat-attention__footer form[action='#{attention_resolutions_path(section: "agenda")}'] input[name=member_id][value='#{@carol.id}']"
  end
end
