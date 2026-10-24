# frozen_string_literal: true

module Reports
  # Whose data a dashboard counts: everything the viewer can access (their
  # own series, anything shared with them, what a linked housemate lets
  # them read, the payments they are the counterparty of), optionally
  # narrowed to one member. A member is anyone who owns at least one series
  # the viewer can access, so a forged ?member_id= can never widen access,
  # only narrow it.
  #
  # Queries take an Audience, never a bare Profile, and scope through
  # #events / #event_ids.
  #
  #   audience.events.of_type(Medication)          # one kind
  #   audience.events.in_section(:agenda)          # tasks + non-medical appointments
  #   audience.events_of_type(Task)                # the same as .events.of_type
  class Audience
    attr_reader :viewer

    # What the viewer's household counts money in: what a report with
    # nothing to sum is shown in.
    def currency = viewer.household.currency

    def initialize(viewer:, member_id: nil)
      @viewer = viewer
      @member_id = member_id.presence&.to_i
    end

    def members
      @members ||= Profile.where(id: member_ids).order(:username).to_a
    end

    def member
      return @member if defined?(@member)

      @member = members.find { |profile| profile.id == @member_id }
    end

    def filtered? = member.present?

    def shared? = members.size > 1

    def events
      scope = Event.accessible_by(viewer)
      filtered? ? scope.where(profile_id: member.id) : scope
    end

    def events_of_type(type) = events.of_type(type)

    def event_ids = events.select(:id)

    def supply_purchases
      scope = SupplyPurchase.accessible_by(viewer)
      filtered? ? scope.where(profile_id: member.id) : scope
    end

    def collections
      scope = Collection.where(id: Collection.accessible_by(viewer).select(:id))
      filtered? ? scope.where(profile_id: member.id) : scope
    end

    def to_param
      filtered? ? { member_id: member.id } : {}
    end

    private

    def member_ids
      Event.accessible_by(viewer).distinct.pluck(:profile_id) | [ viewer.id ]
    end
  end
end
