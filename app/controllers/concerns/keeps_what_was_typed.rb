# frozen_string_literal: true

# A controller that saves the form of something housemates edit together:
# what the form says was typed in it, so that a save refused because
# someone saved meanwhile comes back with only that laid over what they
# saved (EditedTogether#edit_as).
module KeepsWhatWasTyped
  extend ActiveSupport::Concern

  private

  # Of `attributes`, as `record`'s form sent them.
  def typed_fields(record, attributes)
    EditedTogether::TypedFields.new(params[:typed_fields], attributes, under: record.model_name.param_key)
  end
end
