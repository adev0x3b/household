# frozen_string_literal: true

module Households
  # Who is in a household and who is invited, as its page lists them, with
  # how many more the viewer may invite. Each is read once, however many
  # parts of the page ask.
  #
  #   roster = Households::Roster.new(household, viewer: current_profile)
  #   roster.members       # => joined profiles, by name
  #   roster.invitations   # => pending ones, oldest first, with who sent each
  #   roster.invites_left  # => 3, or nil: no limit
  class Roster
    attr_reader :household, :viewer

    def initialize(household, viewer:)
      @household = household
      @viewer = viewer
    end

    def members = (@members ||= household.members.by_name.to_a)
    def invitations = (@invitations ||= household.invitations.includes(:invited_by).oldest_invitation_first.to_a)

    # Everyone counted against the household's places, invited or joined.
    def size = members.size + invitations.size

    def invites_left
      return @invites_left if defined?(@invites_left)

      @invites_left = household.invites_left_for(viewer)
    end

    def room_to_invite? = invites_left.nil? || invites_left.positive?
  end
end
