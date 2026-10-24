# frozen_string_literal: true

# Everything one chat turn asks the assistant to change, as data:
# the user's intents, and the operations covering them (see
# Assistant::Operations). Compiled by Assistant::ChangeSets::Compiler,
# applied atomically by Applier, reverted by Undoer.
#
#   open                  still collecting: something is missing or unclear
#   awaiting_confirmation complete, but risky (a deletion, a possible duplicate, a change
#                         someone else will see): waits for the user's button
#   applied               saved; undo_log says how to revert it (unless undoable is false)
#   undone / cancelled / expired
#
# A chat has at most one set in progress; later calls merge into it. Sets in
# progress expire after EXPIRES_AFTER and are never seen from another chat.
class Assistant::ChangeSet < ApplicationRecord
  EXPIRES_AFTER = 24.hours

  belongs_to :profile
  belongs_to :chat, class_name: "Assistant::Chat", foreign_key: :assistant_chat_id, inverse_of: :change_sets

  enum :status, { open: 0, awaiting_confirmation: 1, applied: 2, undone: 3, cancelled: 4, expired: 5 }

  scope :in_progress, -> { where(status: %i[open awaiting_confirmation]).where(updated_at: EXPIRES_AFTER.ago..) }

  # The chat's set in progress, or a new one; stale ones expire on the way.
  def self.current_for(chat)
    where(chat: chat, status: %i[open awaiting_confirmation]).where(updated_at: ...EXPIRES_AFTER.ago).update_all(status: statuses[:expired])
    where(chat: chat).in_progress.order(:id).last || new(chat: chat, profile: chat.profile)
  end

  def in_progress? = open? || awaiting_confirmation?

  # Deleting something makes a set wait for the user and impossible to undo.
  def deletes? = operations.any? { |op| Assistant::Operations.normalize(op)["op"] == "delete" }

  # The card's rows, from a compile result: [{ intent, summary, status,
  # review, seen_by }].
  def show!(result, status: nil)
    drafts = Assistant::ChangeSets::Review.draft_positions(result.operations)
    rows = result.operations.each_with_index.map do |op, i|
      review = { "draft" => drafts[i], "type" => op.builder.kind } if drafts[i]
      { "intent" => op.intent, "summary" => op.summary, "status" => (status || op.status).to_s, "review" => review,
        "seen_by" => op.seen_by.map(&:display_name).presence }.compact
    end
    update!(display: rows)
  end

  # The names of whoever else will see what the card lists.
  def seen_by = display.flat_map { |row| Array(row["seen_by"]) }.uniq

  # Adds a later call's intents and operations: an operation naming the
  # same thing as one already here (same op, type and identity) updates it.
  # Operation "intent" indexes point into the call's own intents list and
  # are re-pointed at the merged list. Pins are the server's (what a card
  # waiting for the user listed): a later call never brings its own, and an
  # operation it changes is looked up again.
  def merge!(intents:, operations:)
    given = Array(intents).map { |intent| intent.to_s.squish }.reject(&:empty?)
    self.intents = (self.intents + given).uniq(&:downcase)
    merged = self.operations.map(&:deep_dup)

    Array(operations).each do |incoming|
      incoming = incoming.to_h.deep_stringify_keys.except("pinned")
      if (text = given[incoming["intent"].to_i]) && incoming["intent"].to_s.match?(/\A\d+\z/)
        incoming["intent"] = self.intents.index { |intent| intent.casecmp?(text) }
      end
      existing = merged.find { |op| Assistant::Operations.same?(op, incoming) }
      if existing
        existing.delete("pinned")
        existing["fields"] = existing["fields"].to_h.deep_merge(incoming["fields"].to_h)
        existing.merge!(incoming.except("fields").compact)
      else
        merged << incoming
      end
    end
    self.operations = merged
  end
end
