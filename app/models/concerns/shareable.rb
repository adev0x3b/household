# frozen_string_literal: true

# Something its owner can share with a housemate, through a share table of
# its own.
#
#   class Recipe < ApplicationRecord
#     include Shareable
#     shared_through :recipe_shares
#   end
#
# The share table's model includes Share. Sharing is always
# Shares::Create / Shares::Destroy, which tell the person and then call
# the kind's hooks, on_shared and on_unshared: what else a share changes
# (a calendar to redraw, a file's trail) is the kind's to say.
module Shareable
  extend ActiveSupport::Concern

  included do
    class_attribute :share_association, instance_writer: false
  end

  class_methods do
    def shared_through(association)
      self.share_association = association
      has_many association, dependent: :destroy
      has_many :shared_profiles, through: association, source: :profile
    end

    def share_class = reflect_on_association(share_association).klass
  end

  def shares = public_send(share_association)

  # Whether it is shared with `profile` (read from the loaded shares: eager-load
  # the share association when asking of many).
  def shared_with?(profile) = shares.any? { |share| share.profile_id == profile.id }

  # Who sees it: its owner and everyone it is shared with (never the owner
  # twice: Share refuses the owner).
  def people_with_access = [ profile, *shared_profiles ]

  # The housemates it can still be shared with.
  def share_candidates = profile.housemates.where.not(id: shares.map(&:profile_id))

  # Whether it can be shared now (a file only once it is all there).
  def shareable? = true

  # What it is called where sharing names it: the modal, the bell.
  def shared_name = name

  # Each hook is given the share and who made the change (`by:`). Only a
  # file writes who it was into its trail; the other kinds take it as `**`.
  def on_shared(_share, **) = nil
  def on_unshared(_share, **) = nil
end
