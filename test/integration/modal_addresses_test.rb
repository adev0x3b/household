# frozen_string_literal: true

require "test_helper"

# A modal's address opened as a page, in a new tab or after signing in
# again, goes to the page the modal belongs on, never showing the stream
# that opens it (Modals#render_modal). Generated from the routes, like the
# forms test, so a modal is held to it the day its route is drawn.
class ModalAddressesTest < ActionDispatch::IntegrationTest
  include AlicesRecords

  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @day = Date.current
    build_alices_records
  end

  test "every modal's address opened as a page goes to a page" do
    sign_in @alice

    problems = modal_paths.filter_map do |path|
      get path
      next "#{path} answered #{response.status} #{response.media_type}" unless response.redirect?

      landing = response.location
      follow_redirect!
      "#{path} went to #{landing}, which answered #{response.status} #{response.media_type}" unless page?
    end

    assert_operator modal_paths.size, :>=, 30, "the routes' modals were all found"
    assert_empty problems
  end

  test "the admin's modals opened as a page go to the page they belong on" do
    @alice.update!(role: :admin)
    sign_in @alice

    { new_admin_household_path => admin_households_path,
      new_admin_lexicon_path => admin_lexicons_path,
      new_admin_lexicon_case_path("it") => admin_lexicon_path("it"),
      new_assistant_evals_run_path => assistant_evals_path }.each do |modal, page|
      get modal
      assert_redirected_to page
    end
  end

  test "a modal asked for after the session ended opens its page once signed in again" do
    recipe = recipes(:roast_chicken)
    @alice.update!(password: "a-long-password")

    get edit_recipe_path(recipe), as: :turbo_stream
    assert_redirected_to new_profile_session_path

    post profile_session_path, params: { profile: { login: @alice.username, password: "a-long-password" } }
    follow_redirect! while response.redirect?

    assert_equal recipe_path(recipe), path
    assert_predicate self, :page?
  end

  private

  # Every new and edit route whose answer, asked for as Turbo asks, opens a
  # modal (some are pages), and the scanner, a modal that is neither.
  def modal_paths
    @modal_paths ||= Rails.application.routes.routes.filter_map do |route|
      controller, action = route.defaults.values_at(:controller, :action).map(&:to_s)
      next unless route.verb == "GET" && (action.start_with?("new", "edit") || action == "scanner")
      next if controller.start_with?("admin/", "assistant/evals", "profiles/")

      path = route.format(route.required_parts.to_h { |part| [ part, route_value(controller, part) ] })
      get path, as: :turbo_stream
      path if response.successful? && response.body.include?(%(target="#{Modals::FRAME}"))
    end
  end

  def page? = response.successful? && response.media_type == "text/html"
end
