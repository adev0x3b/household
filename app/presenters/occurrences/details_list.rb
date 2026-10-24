# frozen_string_literal: true

# A list on a kind's details (what a dose uses, a meal's recipes) as a
# day's form shows it: the day's own rows, else the series'. On a day of a
# repeating series the form saves to the day or to the whole series, whose
# rows have different ids, so each row names its id on either list
# (matched by `key`), tagged with the target it belongs to for
# apply_to_controller.js, and the series' rows no row stands for are
# dropped when the whole series is chosen. Elsewhere the list is the
# series' own.
class Occurrences::DetailsList
  Row = Data.define(:child, :index, :day_id, :series_id)

  # `prefix` names a row's fields from its index:
  # ->(index) { "meal[details_attributes][meal_recipes_attributes][#{index}]" }
  def initialize(occurrence, association, key:, prefix:)
    @occurrence = occurrence
    @association = association
    @key = key
    @prefix = prefix
  end

  def rows = split.first

  # The hidden inputs that name a row's id: on the series' list when the
  # day can't be saved apart, else one for each target.
  def id_inputs(row)
    name = "#{@prefix.call(row.index)}[id]"
    return [ ({ type: "hidden", name: name, value: row.series_id } if row.series_id) ].compact unless choice?

    [
      ({ type: "hidden", name: name, value: row.day_id, data: { apply_to_scope: "day" } } if row.day_id),
      ({ type: "hidden", name: name, value: row.series_id, **series_only } if row.series_id)
    ].compact
  end

  # The series' rows the whole series drops when it takes the day's list.
  def dropped_inputs
    split.last.flat_map do |child|
      prefix = @prefix.call(child.id)
      [
        { type: "hidden", name: "#{prefix}[id]", value: child.id, **series_only },
        { type: "hidden", name: "#{prefix}[_destroy]", value: "1", **series_only }
      ]
    end
  end

  private

  def event = @occurrence.event
  def choice? = event.persisted? && event.recurring?

  # [rows, the series' children no row stands for]
  def split
    @split ||= begin
      series_children = children(event.persisted? ? event.details : @occurrence.details)
      own_children = choice? && @occurrence.own_details ? children(@occurrence.own_details) : []

      if own_children.empty?
        [ series_children.map { |child| row(child, nil, child.id) }, [] ]
      else
        rows = own_children.map { |child| row(child, child.id, series_children.find { same?(_1, child) }&.id) }
        matched = rows.filter_map(&:series_id)
        [ rows, series_children.reject { matched.include?(_1.id) } ]
      end
    end
  end

  def children(details) = details.public_send(@association).to_a
  def same?(series_child, child) = series_child.public_send(@key) == child.public_send(@key)

  # A row's index is its id, or a negative number for one not saved yet:
  # strong parameters drops any other nested-attributes key.
  def row(child, day_id, series_id)
    Row.new(child: child, index: day_id || series_id || -child.object_id, day_id: day_id, series_id: series_id)
  end

  # An input sent only when the whole series is chosen.
  def series_only = { disabled: true, data: { apply_to_scope: "series", apply_to_held: "1" } }
end
