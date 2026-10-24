# frozen_string_literal: true

# What a person changed on a form before sending it, as the form lists the
# fields by name (typed_fields_controller.js). When the save is refused
# because someone saved the record meanwhile, the form comes back with what
# was typed in these and the other person's values in the rest. A request
# that lists none (the assistant, a form without its script) never says,
# and the form comes back as it was sent.
class EditedTogether::TypedFields
  # A field's name split into its keys: "recipe[steps_attributes][0][body]".
  KEYS = /[^\[\]]+/

  # `attributes` is what the form sent under `under`, its record's key.
  def initialize(names, attributes, under:)
    @names = (Array(names).grep(String).reject(&:empty?) unless names.nil?)
    @attributes = attributes.to_h.with_indifferent_access
    @under = under.to_s
  end

  # Every name the form listed, its record's and the rest, for it to send
  # them again when it is shown again.
  def names = @names.to_a

  def told? = !@names.nil?

  # What was typed of the attributes: a record's own fields one by one,
  # with a nested record's id kept so that it stays the same row, and a
  # list of rows whole when anything in it was, since its rows can't be
  # matched with what the other person did to theirs.
  def attributes
    paths = @names.to_a.map { |name| name.scan(KEYS) }.filter_map { |key, *rest| rest if key == @under && rest.any? }
    pick(@attributes, paths)
  end

  private

  def pick(attributes, paths)
    attributes.each_with_object({}.with_indifferent_access) do |(field, value), typed|
      inner = paths.filter_map { |key, *rest| rest if key == field.to_s }
      next if inner.empty?

      typed[field] = one_record?(value) ? pick(value, inner).merge(value.slice(:id)) : value
    end
  end

  # A nested record arrives as a hash of its fields, a list of rows as a
  # hash keyed by their places or as an array.
  def one_record?(value) = value.is_a?(Hash) && value.keys.none? { |key| key.to_s.match?(/\A\d+\z/) }
end
