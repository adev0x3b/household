# frozen_string_literal: true

require "test_helper"

# The navigation, a drawer on phones and a panel from a tablet up: Home,
# Calendar, Assistant and Messages; the household's sections — each a page
# of the home dashboard, Healthcare and Pantry with their own pages folded
# under them; its people (Links); the admin's pages (the evals among
# them) folded under Admin. The page you're on is marked, and its group
# starts open.
class NavbarTest < ActionDispatch::IntegrationTest
  test "an admin gets the Admin group with the admin's and the assistant's pages; the one they're on is marked and its group open" do
    sign_in(profiles(:alice).tap { _1.update!(role: :admin) })

    get admin_lexicons_path
    assert_select ".navbar-group.is-open .navbar-group-label", text: "Admin"
    assert_select ".navbar-group.is-open button.navbar-group-header[aria-expanded=true][aria-controls=navbar-group-admin]"
    assert_select ".navbar-group.is-open #navbar-group-admin .navbar-link", 8
    [ admin_households_path, admin_deployment_path, admin_settings_path, admin_errors_path, admin_jobs_path,
      assistant_settings_path, assistant_evals_path ].each do |path|
      assert_select ".navbar-group.is-open a.navbar-link[href='#{path}']"
    end
    assert_select ".navbar-group.is-open a.navbar-link[href='#{assistant_settings_path}']", text: /Assistant settings/
    assert_select "a.navbar-link.is-current[aria-current=page][href='#{admin_lexicons_path}']", text: /Languages/
    assert_select ".navbar-group:not(.is-open) a.navbar-group-link[href='#{home_section_path(section: "healthcare")}']", text: /Healthcare/
    assert_select ".navbar-links > a.navbar-link[href='#{assistant_path}']", text: /Assistant/
  end

  test "a member gets the everyday pages, the sections and the people, and nothing of the Admin group" do
    sign_in profiles(:bob)

    get root_path
    assert_select "nav#navbar-sheet.navbar-sheet[aria-label]"
    assert_select ".navbar-sheet .navbar-sheet-handle[data-navbar-target=handle][data-action='pointerdown->navbar#dragStart'] .navbar-handle-pill"
    assert_select ".navbar-sheet a.navbar-sheet-brand[href='#{root_path}'] .navbar-logo-text", text: "Household"
    assert_select ".navbar-topbar button.navbar-burger[data-navbar-target=toggler][aria-controls=navbar-sheet][aria-expanded=false][aria-label=Menu]"
    assert_select "nav.bottom-nav button.bottom-nav__menu[data-navbar-target=toggler][aria-controls=navbar-sheet]"
    assert_select ".navbar-caption", text: "Sections"
    assert_select ".navbar-caption", text: "People"
    assert_select ".navbar-links > a.navbar-link.section--messages[href='#{conversations_path}'] .messages-badge"
    assert_select "a.navbar-link.section--links[href='#{links_path}'] .links-badge"
    assert_select ".navbar-topbar a[href='#{links_path}']", 0
    assert_select ".navbar-sheet a[href='#{household_path}']", 0
    assert_select ".navbar-sheet form", 0
    assert_select ".navbar-group-label", text: "Admin", count: 0
    assert_select "a.navbar-link[href='#{assistant_evals_path}']", 0
    assert_select "a.navbar-link[href='#{admin_lexicons_path}']", 0
    assert_select "a.navbar-link[href='#{assistant_settings_path}']", 0
    assert_select "a.navbar-link[href='#{admin_deployment_path}']", 0
    assert_select "a.navbar-link[href='#{admin_settings_path}']", 0
    assert_select "a.navbar-link[href='#{admin_errors_path}'], a.navbar-link[href='#{admin_jobs_path}']", 0
    assert_select "a.navbar-link.is-current[href='#{root_path}']", text: /Home/
    assert_select "a.navbar-link:not(.is-current)[href='#{calendar_path}']", text: /Calendar/
    assert_select ".navbar-group.section--agenda a.navbar-link.navbar-group-link:not(.is-current)[href='#{home_section_path(section: "agenda")}']", text: /Agenda/
    assert_select ".navbar-group.section--agenda a.navbar-link i.fa-calendar-check"
    assert_select ".navbar-group.section--finance a.navbar-link.navbar-group-link[href='#{home_section_path(section: "finance")}']", text: /Finance/

    get home_section_path(section: "agenda")
    assert_select "a.navbar-link:not(.is-current)[href='#{root_path}']", text: /Home/
    assert_select "a.navbar-link.is-current[aria-current=page][href='#{home_section_path(section: "agenda")}']", text: /Agenda/
  end

  test "a section with pages of its own is a link with a toggle beside it, open on the section's page and on each of its pages" do
    sign_in profiles(:bob)

    get root_path
    assert_select ".navbar-group.section--healthcare:not(.is-open)" do
      assert_select ".navbar-group-header > a.navbar-link.navbar-group-link[href='#{home_section_path(section: "healthcare")}']", text: /Healthcare/
      assert_select ".navbar-group-header > button.navbar-group-toggle[aria-expanded=false][aria-controls=navbar-group-healthcare][aria-label]"
      assert_select "#navbar-group-healthcare a.navbar-link[href='#{collections_path(section: "healthcare")}']", text: /Medical therapies/
      assert_select "#navbar-group-healthcare a.navbar-link[href='#{analytes_path}']"
      assert_select "#navbar-group-healthcare a.navbar-link[href='#{supplies_path}']"
    end
    assert_select ".navbar-group.section--pantry #navbar-group-pantry a.navbar-link[href='#{recipes_path}']"
    # Every section's collections, under the section
    %w[agenda finance pantry].each do |section|
      assert_select ".navbar-group.section--#{section} #navbar-group-#{section} a.navbar-link[href='#{collections_path(section: section)}']", text: /Collections/
    end

    get collections_path(section: "healthcare")
    assert_select ".navbar-group.section--healthcare.is-open .navbar-group-toggle[aria-expanded=true]"
    assert_select ".navbar-group.is-open #navbar-group-healthcare a.navbar-link.is-current[href='#{collections_path(section: "healthcare")}']"
    assert_select "a.navbar-group-link:not(.is-current)[href='#{home_section_path(section: "healthcare")}']"

    get home_section_path(section: "healthcare")
    assert_select ".navbar-group.section--healthcare.is-open a.navbar-group-link.is-current[aria-current=page]"
    assert_select ".navbar-group.section--pantry:not(.is-open)"
  end

  test "a member has no Admin group, and Assistant is current on a chat's page" do
    member = profiles(:bob)
    sign_in member
    chat = Assistant::Chat.start!(profile: member)

    get assistant_chat_path(chat)
    assert_select ".navbar-group-label", { text: "Admin", count: 0 }
    assert_select "a.navbar-link.is-current[href='#{assistant_path}']", text: /Assistant/
  end
end
