# frozen_string_literal: true

# Runs an approved request as the owner, through the same code the owner's
# own action would take. Each kind of request is a step of its own: the
# kind's form save (Apply::SaveForm), a day's mark_completed!
# (Apply::Completion), Occurrences::Destroy (Apply::Destroy), or the
# assistant's operation (OperationRunner), whatever it asked.
#
#   Links::Approvals::Apply.call(approval)   # raises Apply::Failed when it can't be done anymore
module Links
  module Approvals
    class Apply
      # The request can't be done any more. Its reason is a LinkApproval
      # failure; the message says what happened, for the report.
      class Failed < StandardError
        attr_reader :reason

        def initialize(reason, message = reason.to_s)
          @reason = reason
          super(message)
        end
      end

      def self.call(approval) = step_for(approval).call(approval)

      # The step that carries out a request, by what it asks.
      def self.step_for(approval)
        return OperationRunner if approval.from_assistant?

        STEPS.fetch(approval.action_kind)
      end

      # A step runs one kind of request; what every kind needs to find its
      # day is here.
      class Step
        def self.call(approval) = new(approval).call

        def initialize(approval)
          @approval = approval
          @owner = approval.owner
        end

        private

        # The saved day, or the dose the series still schedules at the
        # request's date and time.
        def locate!
          @approval.record || scheduled_day || raise(Failed.new(:gone))
        end

        def scheduled_day
          event = @approval.event
          date = @approval.date
          return unless event && date

          event.occurrences_between(date, date).find { |day| day.key == [ date, @approval.time_string ] }
        end
      end

      class Destroy < Step
        def call
          day = whole_series? ? any_day : locate!
          Pundit.authorize(@owner, day, :destroy?)
          Occurrences::Destroy.call(day, by: @owner, scope: @approval.scope || "occurrence")
        end

        private

        def whole_series? = @approval.scope == "series"

        # Deleting the whole series needs only the series: the day it was
        # asked from may have been deleted since.
        def any_day
          event = @approval.event or raise Failed.new(:gone)
          @approval.record || event.occurrence_on(@approval.date, time: @approval.time_string)
        end
      end

      # Marks the day done or not; its card redraws once the decision commits.
      class Completion < Step
        def call
          day = locate!
          Pundit.authorize(@owner, day, :change_status?)
          day.edited_by(@owner).mark_completed!(@approval.to_complete?)
          ActiveRecord.after_all_transactions_commit { Calendar::DayCardBroadcaster.call(event: day.event) }
        end
      end

      # A new series, or a day's change, through the kind's form save.
      class SaveForm < Step
        def call
          day = (@approval.record if @approval.to_update?)
          raise Failed.new(:gone) if @approval.to_update? && day.nil? && !scheduled_day

          form = Occurrences::FormSave.for(@approval.event_type).new(actor: @owner, owner: @owner, params: @approval.payload, record: day)
          Pundit.authorize(@owner, form.record, form.policy_query)
          form.save or raise Failed.new(:changed, form.record.errors.full_messages.to_sentence)
        end
      end

      STEPS = {
        "create" => SaveForm, "update" => SaveForm, "complete" => Completion, "uncomplete" => Completion, "destroy" => Destroy
      }.freeze
    end
  end
end
