# frozen_string_literal: true

require "test_helper"

# A detail table: its cells carry their column's name, and only a wide
# table stacks its rows on a phone.
class Components::Statistics::DataTableTest < ActiveSupport::TestCase
  test "three columns stay a table on a phone; a fourth makes its rows stack" do
    three = render(%w[Category Total Share])
    four = render(%w[Date Description Category Amount])

    assert_equal [ "stat-table" ], three.at_css("table")["class"].split
    assert_equal %w[stat-table stat-table--stacking], four.at_css("table")["class"].split
    labels = four.css("td").map { |cell| cell["data-label"] }
    assert_equal %w[Date Description Category Amount], labels
  end

  test "a column per key takes its words from the scope, and the numeric ones align right" do
    columns = Components::Statistics::DataTable.columns("home.pantry.lists", :list, :bought, numeric: [ :bought ])

    assert_equal [ I18n.t("home.pantry.lists.columns.list"), I18n.t("home.pantry.lists.columns.bought") ], columns.map(&:label)
    assert_equal [ false, true ], columns.map(&:numeric)
  end

  private

  def render(labels)
    table = Components::Statistics::DataTable.new(caption: "Figures", columns: labels.map { Components::Statistics::DataTable::Column.new(label: _1, numeric: false) })
    Nokogiri::HTML5.fragment(table.call { |t| t.row { labels.each { |label| t.cell { label.downcase } } } })
  end
end
