# frozen_string_literal: true

# Holds what a linked housemate asked to do with the owner's day — create
# a series, change a day, mark it done or not, delete a day or a series —
# as a LinkApproval, and tells the owner. One pending request per dose and
# action from the same person: asking again refreshes it.
#
#   Links::Approvals::Hold.call(requester: current_profile, record: day, kind: :complete)
module Links
  module Approvals
    class Hold
      def self.call(**) = new(**).call

      # From an assistant operation held by Operations::Base#ask_owner_for:
      # the op's pinned spec is the payload, replayed on approval.
      def self.from_operation(op)
        approval = call(requester: op.profile, record: op.approval_record, kind: op.approval_kind, scope: op.fields["scope"],
                        payload: { "spec" => op.pinned_spec }, preview: op.preview_rows, source: :assistant)
        [ { "kind" => "requested", "model" => "LinkApproval", "id" => approval.id } ]
      end

      def initialize(requester:, record:, kind:, scope: nil, payload: {}, preview: [], source: :form)
        @requester = requester
        @record = record
        @event = record.event
        @owner = @event.profile
        @kind = kind.to_s
        @scope = (@kind == "destroy" ? scope.presence || "occurrence" : nil)
        @payload = payload
        @preview = preview
        @source = source
      end

      def call
        link = Link.accepted.find_by(pair_key: Link.key_for(@requester, @owner)) or raise Pundit::NotAuthorizedError, "not linked"

        approval = existing || LinkApproval.new
        approval.update!(attributes(link))
        Notifications::Deliver.call(recipient: @owner, kind: :approval_requested, subject: approval, actor: @requester, title: approval.title,
                                    data: { verb: approval.verb, type: approval.event_type, date: approval.date&.iso8601 },
                                    replace: Notification.unread.approval_requested.find_by(subject: approval))
        Links::Broadcaster.changed(@owner, @requester)
        approval
      end

      private

      def existing
        return unless @event.persisted?

        LinkApproval.pending.find_by(event: @event, date: @record.date, time: @record.time, action_kind: @kind, requester: @requester)
      end

      def attributes(link)
        {
          link: link, requester: @requester, owner: @owner, event_type: @event.type, action_kind: @kind, source: @source,
          status: :pending, event: (@event if @event.persisted?), occurrence_id: (@record.id if @record.persisted?),
          date: @record.date, time: @record.time, scope: @scope, title: title, payload: @payload, preview: @preview,
          base_updated_at: @record.changed_at,
          created_at: Time.current, decided_at: nil, failure: nil
        }
      end

      def title
        @record.event_label.presence || I18n.t("links.things.#{@event.type.underscore}")
      rescue StandardError => e
        Rails.error.report(e, handled: true, context: { event_id: @event.id, step: "approval title" })
        I18n.t("links.things.#{@event.type.underscore}")
      end
    end
  end
end
