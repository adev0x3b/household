# frozen_string_literal: true

require "test_helper"

# The top bar's controls: two slots beside the bell, the search taking one,
# and the rest of a page's actions behind one "more" button, deleting last.
class Components::PageControlsTest < ActiveSupport::TestCase
  test "the first two actions are round buttons, in the order given, and the rest fold behind more" do
    controls = parse(actions: [ action("Edit", "/trips/1/edit"), action("Share", "/trips/1/shares/new"), action("Archive", "/trips/1/archive", method: :post) ])

    assert_equal %w[Edit Share], buttons(controls)
    assert_equal "More actions", controls.at_css("button.page-controls__action.item-menu__button")["aria-label"]
    assert_equal [ [ "Archive", "/trips/1/archive", "post" ] ], entries(controls)
  end

  test "a search takes one of the two slots" do
    controls = parse(search: Components::Icon.new("fa-magnifying-glass"), actions: [ action("New", "/trips/new"), action("Scan", "/trips/scan") ])

    assert_equal %w[New], buttons(controls)
    assert_equal [ [ "Scan", "/trips/scan", nil ] ], entries(controls)
  end

  test "deleting always folds, set apart and last, whatever the order given" do
    destroy = action("Delete", "/trips/1", method: :delete, confirm: "Delete it?", danger: true)
    controls = parse(actions: [ destroy, action("Edit", "/trips/1/edit"), action("Share", "/trips/1/shares/new"), action("Print", "/trips/1/print") ])

    assert_equal %w[Edit Share], buttons(controls)
    assert_equal [ [ "Print", "/trips/1/print", nil ], [ "Delete", "/trips/1", "delete" ] ], entries(controls)
    assert_equal "Delete it?", controls.at_css("a.item-menu__entry--danger")["data-turbo-confirm"]
  end

  test "with nothing to fold there is no more button" do
    controls = parse(actions: [ action("Edit", "/trips/1/edit") ])

    assert_nil controls.at_css(".item-menu")
  end

  test "a press with a method says it to Turbo, asking first when told to, and a toggle that is on says so" do
    controls = parse(actions: [ action("Finish", "/trips/1/finish", method: :patch, confirm: "Finish it?"), action("Freeze", "/freeze", active: true) ])

    finish = controls.at_css("a.page-controls__action[aria-label=Finish]")
    assert_equal [ "/trips/1/finish", "patch", "Finish it?" ], [ finish["href"], finish["data-turbo-method"], finish["data-turbo-confirm"] ]
    assert controls.at_css("a.page-controls__action.is-active[aria-label=Freeze]")
  end

  test "a download is a form posted outside Turbo, its button round like the others" do
    form = parse(actions: [ action("Download", "/files/1/download", download: true) ]).at_css("form")

    assert_equal [ "/files/1/download", "false" ], [ form["action"], form["data-turbo"] ]
    assert_equal "Download", form.at_css("button.page-controls__action")["aria-label"]
  end

  private

  def action(label, href, **) = Components::Action.new(href: href, icon: "fa-circle", label: label, **)

  def parse(**) = Nokogiri::HTML5.fragment(ApplicationController.render(Components::PageControls.new(**), layout: false))

  def buttons(controls) = controls.css("a.page-controls__action").map { _1["aria-label"] }

  def entries(controls) = controls.css("a.item-menu__entry").map { [ _1.text.strip, _1["href"], _1["data-turbo-method"] ] }
end
