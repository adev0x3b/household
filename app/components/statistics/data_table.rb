# frozen_string_literal: true

# Detail table under a chart. Numeric columns align right with tabular
# figures. A table of more than three columns can't fit a phone, so there
# each of its rows becomes a stacked card, every cell labeled by its
# column name (data-label, see _statistics.scss); three columns stay a
# table, which reads in a third of the height.
#
#   columns = Components::Statistics::DataTable.columns("home.healthcare.medications", :name, :adherence, numeric: [ :adherence ])
#   render Components::Statistics::DataTable.new(caption: "…", columns: columns) do |table|
#     rows.each do |row|
#       table.row do
#         table.cell { row.name }
#         table.cell { format_figure(row.rate, :percent) }
#       end
#     end
#   end
class Components::Statistics::DataTable < Components::Base
  STACKS_ABOVE = 3

  Column = Data.define(:label, :numeric)

  # A column per key, named by its words under <scope>.columns.<key>.
  def self.columns(scope, *keys, numeric: [])
    keys.map { |key| Column.new(label: I18n.t("#{scope}.columns.#{key}"), numeric: numeric.include?(key)) }
  end

  def initialize(caption:, columns:)
    @caption = caption
    @columns = columns
  end

  def view_template(&)
    div(class: "stat-table__wrapper") do
      table(class: [ "stat-table", ("stat-table--stacking" if @columns.size > STACKS_ABOVE) ]) do
        caption(class: "is-sr-only") { @caption }
        thead do
          tr do
            @columns.each { |column| th(scope: "col", class: cell_class(column)) { column.label } }
          end
        end
        tbody { yield(self) }
      end
    end
  end

  def row(&)
    @cell_index = 0
    tr(class: "stat-table__row", &)
  end

  def cell(&)
    column = @columns.fetch(@cell_index)
    @cell_index += 1
    td(class: cell_class(column), data: { label: column.label }, &)
  end

  private

  def cell_class(column) = [ "stat-table__cell", ("stat-table__cell--numeric" if column.numeric) ]
end
