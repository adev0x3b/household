# frozen_string_literal: true

require "application_system_test_case"

# A press whose answer draws its own item again, by a broadcast or a page
# refresh, leaves the keyboard where the reader was: on the item drawn
# again, or, when it has left the page, on the next one like it. Otherwise
# the focus falls to the page's body and the next Tab starts from the top.
class FocusAfterLiveChangesTest < ApplicationSystemTestCase
  setup do
    @carol = profiles(:carol) # keeps nothing else, so her pages hold only what is made here
    sign_in @carol
  end

  test "ticking a day done from its circle keeps the focus on the circle, drawn again done" do
    day = task!(profile: @carol, date: Date.current, title: "Laundry")
    visit calendar_path
    assert_listening
    circle = Views::Calendar::Cards::Base.dom_id(day, :toggle)

    focus_on find_by_id(circle)
    press :enter

    assert_selector "##{circle}.task-card__toggle--completed"
    assert_focused find_by_id(circle)
    press :enter

    assert_selector "##{circle}.task-card__toggle--pending"
    assert_focused find_by_id(circle)
  end

  test "a day's form saved from the calendar gives the focus back to its title, though the save drew the card again" do
    day = task!(profile: @carol, date: Date.current, title: "Laundry")
    visit calendar_path
    assert_listening
    title = Views::Calendar::Cards::Base.dom_id(day, :title)

    focus_on find_by_id(title)
    press :enter
    within(".modal") do
      select I18n.t("tasks.status.completed"), from: I18n.t("tasks.form.status_label")
      click_on I18n.t("tasks.form.update")
    end

    assert_no_selector ".modal"
    assert_selector ".task-card--completed"
    assert_focused find_by_id(title)
  end

  test "a missed dose marked skipped hands the focus to the next one, and the last to the page's content" do
    medication!(profile: @carol, date: Date.current - 2, name: "Vitamin D")
    medication!(profile: @carol, date: Date.current - 2, name: "Iron")
    visit root_path
    first, second = all(".stat-attention__resolve button", count: 2).to_a

    press_tab_until first
    press :enter

    assert_selector ".stat-attention__resolve button", count: 1
    assert_focused find_by_id(second[:id])
    press :enter

    assert_no_selector ".stat-attention"
    assert_focused find_by_id("content")
  end

  test "an item ticked into the folded basket hands the focus to the next one to buy, and the last to the way to finish" do
    list = GroceryList.create!(profile: @carol, name: "Saturday market")
    visit grocery_list_path(list)
    add_to_list "2 kg flour", "6 pcs eggs"
    first, second = all(".grocery-list-item-row__main", count: 2).map { _1[:id] }

    focus_on find_by_id(first)
    press :enter

    assert_selector ".grocery-list-basket__rows .grocery-list-item-row", count: 1, visible: :all
    assert_focused find_by_id(second)
    press :enter

    assert_focused find_by_id(Views::GroceryLists::Items::FINISH_ID)
  end

  test "an item removed from the list hands the focus to the next one to buy" do
    list = GroceryList.create!(profile: @carol, name: "Saturday market")
    visit grocery_list_path(list)
    add_to_list "2 kg flour", "6 pcs eggs"
    first, second = all(".grocery-list-item-row", count: 2).to_a
    next_tick = second.find(".grocery-list-item-row__main")[:id]

    focus_on first.find(:link_or_button, I18n.t("grocery_list_items.destroy"))
    press :enter

    assert_selector ".grocery-list-item-row", count: 1
    assert_focused find_by_id(next_tick)
  end

  test "a housemate taken off a file's list hands the focus to the next one's button, and the last to the list" do
    upload = keep_file(@carol)
    Shares::Create.call(upload, with: profiles(:alice), by: @carol)
    Shares::Create.call(upload, with: profiles(:bob), by: @carol)
    visit upload_path(upload)
    list = Views::Shares::List.dom_id(upload, :page)
    first, second = all("##{list} .share-list__person a", count: 2).map { _1[:id] }

    focus_on find_by_id(first)
    press :enter

    assert_selector "##{list} .share-list__person", count: 1
    assert_focused find_by_id(second)
    press :enter

    assert_selector "##{list} .empty-state"
    assert_focused find_by_id(list)
  end

  test "in the share modal, the focus stays on the list of people drawn again with it" do
    recipe = @carol.recipes.create!(name: "Lentil soup")
    Shares::Create.call(recipe, with: profiles(:alice), by: @carol)
    Shares::Create.call(recipe, with: profiles(:bob), by: @carol)
    visit recipes_path
    within("#recipe_#{recipe.id}") do
      click_on I18n.t("recipes.card.more")
      click_on I18n.t("recipes.card.share")
    end
    second = all(".modal .share-list__person a", count: 2).last[:id]

    focus_on find(".modal .share-list__person a", match: :first)
    press :enter

    assert_selector ".modal .share-list__person", count: 1
    assert_focused find_by_id(second)
  end

  test "a public link revoked hands the focus to the next live one's button" do
    upload = keep_file(@carol)
    2.times { mint_link(upload) }
    visit upload_path(upload)
    first, second = all(".upload-links a.item-action", count: 2).map { _1[:id] }

    focus_on find_by_id(first)
    press :enter
    within("dialog#confirm_dialog[open]") { click_on I18n.t("upload_links.panel.revoke") }

    assert_selector ".upload-links a.item-action", count: 1
    assert_focused find_by_id(second)
  end

  test "an invitation taken back hands the focus to the next one's, and one renewed keeps it" do
    alice = profiles(:alice)
    dana, erin = %w[dana erin].map { Households::Invite.call(alice.household, inviter: alice, email: "#{_1}@example.com").profile }
    sign_in alice
    visit household_path
    renew = Views::Households::People.button_id(erin, :renew)

    focus_on find_by_id(Views::Households::People.button_id(dana, :cancel))
    press :enter
    within("dialog#confirm_dialog[open]") { click_on I18n.t("households.people.cancel") }

    assert_selector ".household__row--invited", count: 1
    assert_focused find_by_id(renew)
    press :enter
    within("dialog#confirm_dialog[open]") { click_on I18n.t("households.people.renew") }

    assert_selector ".household__link"
    assert_focused find_by_id(renew)
  end

  test "in the bell, older notifications leave the focus on the last row before them, and marking all read keeps it on the button" do
    recipe = recipes(:roast_chicken)
    (Notifications::BellPage::SIZE + 1).times do
      Notification.create!(profile: @carol, actor: profiles(:alice), kind: :shared, subject: recipe, subject_title: recipe.name)
    end
    visit root_path
    find(".notifications__bell").click
    last_shown = all(".notifications__item", count: Notifications::BellPage::SIZE).last

    focus_on find_by_id(Views::Notifications::Older::ID)
    press :enter

    assert_no_selector "##{Views::Notifications::Older::ID}"
    assert_focused last_shown
    mark_all = find_button(I18n.t("notifications.mark_all_read"))
    focus_on mark_all
    press :enter

    assert_no_selector ".notifications__item.is-unread"
    assert_focused mark_all
  end

  private

  # Typed into the list's quick add one line at a time, each waited for.
  def add_to_list(*lines)
    lines.each.with_index(1) do |line, count|
      fill_in I18n.t("grocery_list_items.quick_add.label"), with: line
      find_field(I18n.t("grocery_list_items.quick_add.label")).send_keys(:enter)
      assert_selector ".grocery-list-item-row", count: count
    end
  end

  # Puts the focus on an element without pressing it: the month's page has
  # a "+" on every day before today's, and the test is about what happens
  # after the press, not about reaching it.
  def focus_on(element)
    execute_script("arguments[0].focus()", element)
    assert_focused element
  end
end
