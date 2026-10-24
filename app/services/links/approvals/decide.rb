# frozen_string_literal: true

# The owner answers a LinkApproval: approving does it as the owner
# (Links::Approvals::Apply), or records why it couldn't be done, and
# declining just closes it. The asker hears how it went; the owner's bell
# row loses its buttons; both Links pages redraw.
module Links
  module Approvals
    class Decide
      class Decided < StandardError; end

      def self.call(approval, approve:)
        approval.with_lock do
          raise Decided unless approval.live? && approval.link.accepted?

          if approve
            begin
              LinkApproval.transaction(requires_new: true) { Apply.call(approval) }
              approval.update!(status: :approved, decided_at: Time.current)
            rescue Apply::Failed, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError => e
              failure = failure_of(e)
              # It passed its checks when it was asked for, so a change that
              # no longer saves may be the app's mistake, not only a race.
              Rails.error.report(e, handled: true, context: { link_approval_id: approval.id }) if failure == :changed
              approval.update!(status: :failed, failure: failure, decided_at: Time.current)
            end
          else
            approval.update!(status: :declined, decided_at: Time.current)
          end
        end
        # The lock read it again: its two people, in one query.
        ActiveRecord::Associations::Preloader.new(records: [ approval ], associations: %i[requester owner]).call

        Notifications::Deliver.call(recipient: approval.requester, kind: :"approval_#{approval.status}", subject: approval, actor: approval.owner,
                                    title: approval.title, data: { verb: approval.verb, type: approval.event_type, failure: approval.failure })
        settled(approval)
        approval
      end

      # Its question is answered (or taken back): bell rows and pages follow.
      def self.settled(approval)
        Notification.where(subject: approval, kind: :approval_requested).find_each { |notification| Notifications::Broadcaster.refreshed(notification) }
        Links::Broadcaster.changed(approval.owner, approval.requester)
      end

      # Why it couldn't be done, as a LinkApproval failure: the reader's page
      # words it, in the reader's language.
      def self.failure_of(error)
        case error
        when Apply::Failed then error.reason
        when ActiveRecord::RecordNotFound then :gone
        when Pundit::NotAuthorizedError then :not_allowed
        else :changed
        end
      end
    end
  end
end
