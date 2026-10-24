# frozen_string_literal: true

require "application_system_test_case"

# A modal's form and its required fields, as a keyboard and a screen reader
# meet them: nothing is red before the reader has done anything, Save is
# always there to press, and pressing it with something missing says what,
# under the field, where the focus is taken.
class RequiredFieldsTest < ApplicationSystemTestCase
  setup do
    sign_in profiles(:alice)
    visit books_path
    click_on I18n.t("books.index.new")
  end

  # The page has fields of its own, behind the modal; these are the form's.
  def find_field(...) = within(".modal") { super }
  def save = find(".modal__footer input[type=submit]")

  test "a new form shows nothing missing; Save is reached by keyboard and takes the reader to the first field to fill" do
    title = find_field(I18n.t("books.form.title_label"))

    assert_no_selector ".field.is-missing"
    assert_no_selector ".modal__field-tooltip", visible: true
    assert_nil title["aria-invalid"]
    press_tab_until save
    press :enter

    assert_selector ".field.is-missing", minimum: 1
    assert_focused title, "the focus is on the first field to fill"
    assert_equal "true", title["aria-invalid"]
    message = find_by_id(title["aria-describedby"].split.last)
    assert_equal I18n.t("modal.field_required_hint", field: I18n.t("books.form.title_label")), message.text
    assert_no_changes(-> { Book.count }) { assert_current_path books_path }
  end

  test "Enter in a field with something missing is answered the same way, though the browser checks the form first" do
    visit collections_path(section: "agenda")
    click_on I18n.t("collections.sections.agenda.index.new")
    name = find_field(I18n.t("collections.form.name_label"))

    name.send_keys(:enter)

    assert_selector "##{name["id"]}_missing", text: I18n.t("modal.field_required_hint", field: I18n.t("collections.form.name_label"))
    assert_focused name
  end

  test "a field filled in and emptied again says it is missing once the reader leaves it, and stops once it is filled" do
    title = find_field(I18n.t("books.form.title_label"))
    message = "##{title["id"]}_missing"

    title.send_keys("Dune", [ :control, "a" ], :backspace)
    assert_no_selector message, visible: true
    find_field(I18n.t("books.form.author_label")).click
    assert_selector message, visible: true
    assert_includes title["aria-describedby"].to_s.split, "#{title["id"]}_missing"

    title.send_keys("Dune")
    assert_no_selector message, visible: true
    assert_nil title["aria-invalid"]
    assert_nil title["aria-describedby"]
  end
end
