# frozen_string_literal: true

# Adds operations to the chat's change set in progress and moves it on:
# applied when complete and safe, held for details, or held for the user's
# button (a deletion, a possible duplicate, a change someone else will
# see). Every write tool goes through
# here, so they all answer the model the same way:
#
#   status "saved"            applied; it can be undone from the card
#   status "needs_input"      something is missing or unclear (see operations)
#   status "waiting_for_user" needs the user's OK
#
# What is ready doesn't wait for what isn't: when some operations need
# details or the user's OK, the ready ones are saved now as a set of their
# own, undone on its own, and the rest stay in progress. Both happen in one
# transaction, so a call that fails saves nothing, and the cards are pushed
# only once it has committed.
#
# Raises Mistake for problems in how the model described the change (not
# details the user still has to give), so it corrects the call itself.
module Assistant
  module ChangeSets
    class Submit
      class Mistake < StandardError; end

      UNRESOLVED = %i[ambiguous invalid missing].freeze

      def self.call(...) = new(...).call

      # confirm: the user said to go ahead although something similar exists.
      def initialize(chat:, operations:, confirm: false)
        @chat = chat
        @operations = operations
        @confirm = confirm
      end

      def call
        set = take_operations
        result = Compiler.call(set)
        keep_understood(set, result)
        ActiveRecord::Base.transaction { advance(set, result) }
      end

      private

      def take_operations
        set = ChangeSet.current_for(@chat)
        drop_unresolved(set)
        set.merge!(intents: [], operations: @operations)
        set.acknowledged_warnings |= set.shown_warnings if @confirm
        set.save!
        set
      end

      # A new update, complete or delete for the same kind of record replaces
      # one still waiting for its record (the model's corrected reference:
      # "the Moretti visit on the 25th" after "the Moretti visit" matched
      # two), instead of leaving the old one to block the set.
      def drop_unresolved(set)
        incoming = Array(@operations).map { |spec| Operations.normalize(spec) }.reject { |spec| spec["op"] == "create" }
        return if incoming.empty? || set.operations.empty?

        kinds = incoming.to_set { |spec| [ spec["op"], spec["type"] ] }
        stale = Compiler.call(set).operations.select do |op|
          kinds.include?([ op.op, op.type ]) && UNRESOLVED.include?(op.status)
        end
        set.operations = set.operations.reject.with_index { |_, i| stale.any? { |op| op.index == i } } if stale.any?
      end

      # The set keeps its operations as they were understood (normalized,
      # misfiled parts split out). Broken ones are dropped: they are
      # reported to the model and come back corrected.
      def keep_understood(set, result)
        invalid = result.operations.select { |op| op.status == :invalid }
        set.update!(operations: (result.operations - invalid).map(&:spec),
                    shown_warnings: set.shown_warnings | result.operations.flat_map(&:warning_keys))
        raise Mistake, invalid.map { |op| "#{op.op} #{op.type}: #{op.problems.join("; ")}." }.join(" ") if invalid.any?
        raise Mistake, "Nothing to change was given." if result.operations.empty?
      end

      def advance(set, result)
        ready, held = split(result.operations)
        return respond(set, result) unless ready.any? && held.any? && independent?(result.operations)

        saved = save_now(set, ready)
        set.update!(operations: held.map(&:spec))
        with_saved(respond(set, Compiler.call(set)), saved)
      end

      # What can be saved now and what waits. A dose using a supply this set
      # buys waits with the purchase while the purchase waits.
      def split(operations)
        ready, held = operations.partition { |op| op.status == :ready }
        return [ ready, held ] if held.empty?

        waiting, ready = ready.partition(&:waits_for_purchase?)
        [ ready, held + waiting ]
      end

      # Operations naming each other ($handles) are saved together or not at all.
      def independent?(operations)
        operations.none? { |op| op.spec["as"].present? || op.ref.to_s.start_with?("$") }
      end

      def save_now(set, operations)
        done = ChangeSet.create!(chat: @chat, profile: @chat.profile, operations: operations.map(&:spec),
                                 acknowledged_warnings: set.acknowledged_warnings)
        applier = Applier.new(done)
        applier.call
        show(done)
        applier.summaries
      end

      def respond(set, result)
        set.show!(result) unless result.ready?
        case result.status
        when :ready then apply(set, result)
        when :confirm then wait_for_user(set, result)
        else ask_for_input(set, result)
        end
      end

      def apply(set, result)
        applier = Applier.new(set)
        applier.call
        show(set)
        notes = result.operations.flat_map { |op| Array(op.notes) }
        { change_set_id: set.id, status: "saved", saved: applier.summaries, notes: notes.presence,
          next: saved_next(result.operations, notes) }.compact
      end

      # What the card lists is what the button applies: each operation
      # keeps the records it was checked against (Operations::Base#pin).
      def wait_for_user(set, result)
        set.update!(status: :awaiting_confirmation, operations: result.operations.map(&:pinned_for_confirmation))
        show(set)
        { change_set_id: set.id, status: "waiting_for_user", changes: result.operations.map(&:to_result),
          next: confirm_next(result.operations) }
      end

      def ask_for_input(set, result)
        set.update!(status: :open)
        show(set)
        { change_set_id: set.id, status: "needs_input", changes: result.operations.map(&:to_result),
          next: needs_input_next(result.operations) }
      end

      # The chat's card for the set, once the call's transaction commits.
      def show(set) = ActiveRecord.after_all_transactions_commit { Assistant::Broadcaster.change_set(set.reload) }

      # What was saved, and what the operations noted on the way (a field
      # not understood and left out, the most recent one assumed): the user
      # hears that too, not only what went in.
      def saved_next(operations, notes)
        asked = operations.select(&:held?).map { |op| op.approval_owner.display_name }.uniq
        if asked.any?
          return "#{"The rest is saved. " if asked.size < operations.size}NOT SAVED: #{asked.to_sentence} #{asked.one? ? "was" : "were"} " \
                 "asked to OK the change to their #{asked.one? ? "item" : "items"} — it happens when they approve it. Tell the user that plainly."
        end
        return "Saved, with notes: #{notes.join("; ")}. Tell the user what was saved and what the notes say; they can undo it with the Undo button." if notes.any?

        "Saved. Tell the user in plain words what was saved; they can undo it with the Undo button."
      end

      # An operation's own notes (Delete's "this series keeps repeating")
      # say more than the general text, so the first one leads.
      def confirm_next(operations)
        note = operations.flat_map { |op| Array(op.notes) }.first
        "NOT SAVED YET. #{"#{note} " if note}Tell the user what needs their OK (a deletion can't be undone; something " \
          "similar already exists; someone else would see the change). They press Apply on the card — or, for something " \
          "similar, they may tell you to go ahead: then make the same call again with confirm: true."
      end

      # A missing field is often not really missing: a warning already
      # points at an existing record that covers what the model is trying to
      # create (a series it's about to duplicate). That comes first: asking
      # about the missing field would just recreate the same near-duplicate
      # with one more detail.
      def needs_input_next(operations)
        hint = operations.flat_map { |op| Array(op.warnings) }.filter_map { |w| w["hint"] }.first
        return "NOT SAVED YET. #{hint}" if hint

        "NOT SAVED YET. Ask the user, in one short question, for what is listed as missing, or which one " \
          "they mean (candidates). When they answer, call the same tool again with just the new details."
      end

      # Part of the call was saved, part still waits.
      def with_saved(response, saved)
        response.merge(saved: saved, next: "The saved part is done (they can undo it with the Undo button). The rest is " + response[:next])
      end
    end
  end
end
