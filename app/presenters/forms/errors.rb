# frozen_string_literal: true

# What a form that didn't save says went wrong, in the words of its labels.
# Rails words an error on a row of a form's list under a name it builds
# from the path ("Recipe ingredients quantity"), which no locale file has,
# so each error is followed back to the record that failed, worded by that
# record, and told with the list and the row it is on.
#
#   words = Forms::Errors.new(recipe)
#   words.sentences                  # the form's summary
#   words.for(:name)                 # under the name's field
#   words.rows(:recipe_ingredients)  # under each row of the ingredients
class Forms::Errors
  def initialize(record)
    @record = record
  end

  # Whether the record has anything to say; a row of a list that is no
  # association (a form object's own rows) is told by its record alone.
  def any? = @record.errors.any?

  # Every error, one sentence each, for the form's summary. Two errors
  # that read the same are said once.
  def sentences = worded.map(&:sentence).uniq

  # What is wrong with one field, by its path on the form's record
  # (`:name`, or `:"details.area"` for a kind's field on a day's form).
  def for(path)
    worded.select { |error| error.path == path.to_s && error.rows.empty? }.map(&:message).uniq
  end

  # What is wrong with each row of one of the form's lists, by the row's
  # place in the list from zero. A row without errors has none.
  def rows(path)
    found = worded.select { |error| error.path.start_with?("#{path}.") && error.rows.first&.position }
      .group_by { |error| error.rows.first.position }
      .transform_values { |errors| RowErrors.new(errors.map(&:within_row)) }
    found.default = RowErrors.new([])
    found
  end

  # One row's errors: all of them, worded as the row shows them, or those
  # about one of its fields.
  class RowErrors
    def initialize(errors)
      @errors = errors
    end

    def any? = @errors.any?
    def sentences = @errors.map(&:sentence).uniq

    def for(attribute)
      @errors.select { |error| error.rows.empty? && error.attribute == attribute.to_sym }.map(&:message).uniq
    end
  end

  # An error as the form tells it: the path it has on the form's record,
  # the rows of lists it crossed on the way to the record that failed, the
  # field there, and the sentence that record words it with.
  Worded = Data.define(:path, :rows, :attribute, :message) do
    def sentence = rows.reverse.reduce(message) { |words, row| row.sentence(words) }

    # The same error told from inside its first row, as that row shows it.
    def within_row = with(rows: rows.drop(1))
  end
  private_constant :Worded

  private

  def worded = @worded ||= @record.errors.map { |error| word(error) }

  # An error on a part of the record (its details, a row of one of its
  # lists, or another record whose errors were copied onto it) keeps the
  # error it came from, down to the record that failed. The field is named
  # by the last part crossed into: errors copied whole keep the field the
  # form shows (a day's form names its series' fields as the day's).
  def word(error)
    path = error.attribute.to_s
    namer = error.base
    rows = []
    while error.is_a?(ActiveModel::NestedError)
      inner = error.inner_error
      if crossed?(error, inner)
        namer = inner.base
        row = row_between(error, inner)
        rows << row if row
      end
      error = inner
    end
    Worded.new(path: path, rows: rows, attribute: error.attribute,
               message: ActiveModel::Error.full_message(error.attribute, error.message, namer))
  end

  def crossed?(error, inner) = error.attribute.to_s != inner.attribute.to_s

  # The row an error crossed into, when its record holds the failed one in
  # a list. A part the record has one of (a kind's details) is not a list.
  def row_between(error, inner)
    name = error.attribute.to_s.delete_suffix(".#{inner.attribute}")
    holder = error.base
    # A form object (the first setup's steps) has no associations to cross.
    return unless holder.class.respond_to?(:reflect_on_association)
    return unless holder.class.reflect_on_association(name.to_sym)&.collection?

    Row.new(holder, name, inner.base)
  end

  # A row of a list, as the form draws it: in the order the list holds its
  # rows, numbered from one, and not numbered at all when it is the only one.
  class Row
    attr_reader :position

    def initialize(holder, name, record)
      @list = holder.class.human_attribute_name(name)
      @rows = holder.association(name.to_sym).target
      @position = @rows.index(record)
    end

    def sentence(message)
      if @position.nil? || @rows.one?
        I18n.t("form.errors.alone", list: @list, message: message)
      else
        I18n.t("form.errors.row", list: @list, number: @position + 1, message: message)
      end
    end
  end
  private_constant :Row
end
