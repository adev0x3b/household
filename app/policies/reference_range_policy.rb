# frozen_string_literal: true

# A reference range is part of its analyte, so it is the analyte's owner's.
class ReferenceRangePolicy < ApplicationPolicy
  def create? = owner?
  def update? = owner?
  def destroy? = owner?

  private

  def owning_record = record.analyte
end
