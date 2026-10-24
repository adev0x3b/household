# frozen_string_literal: true

# A day's row, and a day's row of its kind's fields, hold only what differs
# from the series: a column left NULL reads the series' value, the way an
# iCalendar instance carries only what it overrides. The includer names
# the fields with `inherits` and says where the series' values come from.
module InheritsFromSeries
  extend ActiveSupport::Concern

  included do
    class_attribute :inherited_fields, default: [], instance_writer: false, instance_predicate: false
  end

  class_methods do
    # Each field gets a reader that falls back to the series and an `own_`
    # reader for the column itself, for a form that shows what the day
    # alone holds.
    def inherits(*names)
      self.inherited_fields = inherited_fields + names.map(&:to_s)
      names.each do |name|
        define_method(name) do
          own = self[name]
          own.nil? && follows_series? ? inherits_from.public_send(name) : own
        end
        define_method(:"own_#{name}") { self[name] }
      end
    end
  end

  # Assigns values as the row's own, keeping only what differs from the
  # series: a field that ends up equal to the series' value, as its column
  # would hold it, goes back to NULL. So the day keeps following the series
  # there, and a field set back to the series' value follows it again.
  def assign_own(values)
    assign_attributes(values)
    return unless follows_series?

    normalize_for_comparison
    inherited_fields.each { |name| self[name] = nil if !self[name].nil? && self[name] == inherits_from[name] }
  end

  private

  # The record whose values a NULL column reads.
  def inherits_from = raise(NotImplementedError, "#{self.class.name}#inherits_from")

  # Whether this row is a day's; the series' own row has nothing to inherit.
  def follows_series? = true

  # What a kind does to its values before storing them, so a day's are
  # compared with the series' as they will be saved.
  def normalize_for_comparison; end
end
