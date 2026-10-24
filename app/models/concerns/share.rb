# frozen_string_literal: true

# One person's access to one shared thing: a row in the thing's own share
# table, so each kind keeps its foreign keys.
#
#   class RecipeShare < ApplicationRecord
#     include Share
#     shares :recipe
#   end
#
# Never with the thing's owner, once per person, and only with a housemate
# of the owner. A kind adds what is its own (UploadShare: only a ready file).
module Share
  extend ActiveSupport::Concern

  included do
    class_attribute :thing_name, instance_writer: false
    belongs_to :profile
  end

  class_methods do
    def shares(thing)
      self.thing_name = thing
      belongs_to thing
      validates :profile_id, uniqueness: { scope: :"#{thing}_id" }
      validate :never_with_the_owner
      validates_within_household :profile, of: -> { self.thing&.profile }
    end

    def thing_key = :"#{thing_name}_id"
  end

  def thing = public_send(thing_name)

  private

  def never_with_the_owner
    errors.add(:profile_id, :invalid) if thing && profile && thing.profile_id == profile_id
  end
end
