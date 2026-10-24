# frozen_string_literal: true

module Occurrences
  # What the viewer may do with a day of a series, as its policy answers
  # (never "is it mine?" alone): a linked housemate's item can be theirs
  # to change, to ask about, or only to see. The cards and the form ask it
  # instead of the policy, so nobody signed in is one answer, given here.
  #
  #   access = Occurrences::Access.new(day, viewer)
  #   access.allows?(:destroy?)   # may delete it
  #   access.asks?(:destroy?)     # may, once the owner has said yes
  class Access
    attr_reader :viewer

    def initialize(occurrence, viewer)
      @occurrence = occurrence
      @viewer = viewer
    end

    def viewer? = @viewer.present?

    def owner? = viewer? && @occurrence.event.profile_id == @viewer.id

    # Whether the viewer may do what the policy's `query` asks (`:update?`).
    # A yes may still mean "ask": see #asks?.
    def allows?(query)
      return false unless viewer?

      policy.public_send(query)
    end

    # Whether what the viewer may do waits for the owner's OK.
    def asks?(query) = viewer? && policy.needs_approval?(query)

    # Whose calendar a new series of this kind may go on: the viewer's own,
    # and a linked housemate's who lets them add there. A series that
    # exists is already on one.
    def creatable_owners
      return [] unless viewer? && @occurrence.event.new_record?

      Links::Permissions.for(@viewer).creatable_owners(@occurrence.event.type)
    end

    private

    def policy = @policy ||= Pundit.policy!(@viewer, @occurrence)
  end
end
