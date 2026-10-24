# frozen_string_literal: true

# What one may do with a day of a series: the owner everything; someone the
# series (or its collection) is shared with may see and change it; a linked
# housemate what the owner's grant on that kind says (EventAuthorizable). A
# kind with rules of its own names its policy (Event.policy_class), and a
# day resolves to it through Occurrence#policy_class.
class OccurrencePolicy < ApplicationPolicy
  include EventAuthorizable

  def create? = creatable?
  def edit? = writable?
  def update? = writable?
  def change_status? = writable?
  def destroy? = deletable?
end
