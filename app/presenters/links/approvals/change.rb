# frozen_string_literal: true

# One line of what a linked housemate asks to change, as the owner reads
# it: the field's name, and its value before and after, with an enum's
# value in words and a day in the reader's language. A field is the day's
# (Occurrence), its kind's details', or the series' own.
#
#   change = Links::Approvals::Change.new({ "attribute" => "priority", "from" => "low", "to" => "high" }, kind: Task)
#   change.field  # => "Priority"
#   change.to     # => "High"
class Links::Approvals::Change
  # Fields an assistant's change names that are no column of the kind: the
  # rule a series repeats by, and the amount of a payment.
  OWN_WORDS = %w[recurrence amount].freeze

  def initialize(row, kind:)
    @attribute = row["attribute"]
    @from = row["from"]
    @to = row["to"]
    @kind = kind
  end

  def field
    return I18n.t("links.approvals.fields.#{@attribute}") if OWN_WORDS.include?(@attribute) && !column?

    @kind.human_attribute_name_for(@attribute)
  end

  # Nil when the field was empty before, or is cleared.
  def from = words(@from)
  def to = words(@to)

  private

  def column? = [ Occurrence, @kind.details_class, @kind ].any? { |model| model.column_names.include?(@attribute) }

  def words(raw)
    return if raw.blank?

    if enum?
      I18n.t("#{@kind.model_name.route_key}.#{@attribute}.#{raw}", default: raw.to_s.humanize)
    elsif @kind.attribute_type_for(@attribute).type == :date
      day(raw)
    else
      raw
    end
  end

  # A skipped day's reason is worded like an enum, though it is a string the
  # kind lists (`skip_reasons`).
  def enum?
    @attribute == "skipped_reason" || [ Occurrence, @kind.details_class ].any? { |model| model.defined_enums.key?(@attribute) }
  end

  # The preview keeps a day as ISO 8601; one that doesn't parse is shown as
  # it was kept, and reported, since nothing the app writes looks like that.
  def day(raw)
    I18n.l(Date.iso8601(raw), format: :long)
  rescue Date::Error => e
    Rails.error.report(e, handled: true, context: { kind: @kind.name, attribute: @attribute, value: raw })
    raw
  end
end
