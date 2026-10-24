# frozen_string_literal: true

require "test_helper"

# The app's own "are you sure?": a native dialog the controller fills in,
# whose two buttons close it with their own answer.
class Components::ConfirmDialogTest < ActiveSupport::TestCase
  test "it is named by its question and closed by either of its buttons" do
    dialog = parse(Components::ConfirmDialog.new).at_css("dialog#confirm_dialog")

    assert_equal "confirm-dialog", dialog["data-controller"]
    assert_equal "confirm_dialog_question", dialog["aria-labelledby"]
    assert dialog.at_css("p#confirm_dialog_question[data-confirm-dialog-target=question]")
    assert_equal "dialog", dialog.at_css("form")["method"], "a dialog form closes the dialog, and Turbo leaves it alone"
    assert_equal([ %w[cancel Cancel], %w[confirm Confirm] ], dialog.css("button[type=submit]").map { [ _1["value"], _1.text ] })
  end

  test "Cancel has the focus when it opens, so a stray Enter never confirms" do
    dialog = parse(Components::ConfirmDialog.new)

    assert dialog.at_css("button[value=cancel]").has_attribute?("autofocus")
    assert_not dialog.at_css("button[value=confirm]").has_attribute?("autofocus")
  end

  test "it carries its default words in the reader's language" do
    words = I18n.with_locale(:it) { JSON.parse(parse(Components::ConfirmDialog.new).at_css("dialog")["data-confirm-dialog-words-value"]) }

    assert_equal({ "confirm" => "Conferma", "dismiss" => "Annulla" }, words)
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call)
end
