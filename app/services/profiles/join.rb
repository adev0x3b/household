# frozen_string_literal: true

# What someone has from the moment they are in the household: the standard
# analytes, so a lab result can be typed before anyone builds a catalog, and
# a place in the household's conversation, with its history, so opening
# Messages only reads. Whoever makes a person who is in, rather than an
# invitation, calls it in the same transaction. Calling it again changes
# nothing.
#
#   Profiles::Join.call(profile)   # => profile
module Profiles
  class Join
    def self.call(profile)
      raise ArgumentError, "#{profile.email} hasn't accepted their invitation" if profile.invitation_pending?

      Analyte.seed_standards_for!(profile)
      Conversation.household_conversation(profile.household)
      profile
    end
  end
end
