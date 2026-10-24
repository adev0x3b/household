# frozen_string_literal: true

# Everyone joins their household's conversation as they join the household
# (Profile), where the list of conversations used to make it the first time
# someone opened Messages. The households already there get theirs now,
# with everyone who has joined them in it.
class JoinEveryoneToTheirHouseholdsConversation < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      # zero-downtime: the version still serving makes the same rows on the way into Messages, and the unique indexes skip a row already there.
      # Kind 1 is a household's conversation (Conversation.kinds).
      execute(<<~SQL.squish)
        INSERT INTO conversations (household_id, kind, created_at, updated_at)
        SELECT households.id, 1, now(), now() FROM households
        ON CONFLICT (household_id) WHERE kind = 1 DO NOTHING
      SQL
      execute(<<~SQL.squish)
        INSERT INTO conversation_participants (conversation_id, profile_id, joined_at, created_at, updated_at)
        SELECT conversations.id, profiles.id, now(), now(), now()
        FROM conversations JOIN profiles ON profiles.household_id = conversations.household_id
        WHERE conversations.kind = 1 AND profiles.invitation_token IS NULL
        ON CONFLICT (conversation_id, profile_id) DO NOTHING
      SQL
    end
  end

  # The rows stay: they are what the app would have made anyway.
  def down; end
end
