# frozen_string_literal: true

# What one lets a linked housemate do with one's items is one's own to set.
class LinkGrantPolicy < ApplicationPolicy
  def update? = record.grantor_id == user.id
end
