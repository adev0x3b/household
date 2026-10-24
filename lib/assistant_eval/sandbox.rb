# frozen_string_literal: true

# A throwaway profile for replays and evals, in a household of its own: no
# records except an "B12" therapy (a healthcare Collection), so the real
# user's drafts and data can't steer the model. Always created inside a
# transaction that is rolled back.
module AssistantEval
  module Sandbox
    module_function

    def profile!
      token = SecureRandom.hex(4)
      profile = Profile.create!(household: Household.create!(name: "Try #{token}"), username: "try-#{token}", email: "try-#{token}@example.invalid",
                                password: SecureRandom.hex(16), first_name: "Try")
      Profiles::Join.call(profile)
      Collection.create!(profile: profile, name: "B12", section: "healthcare")
      profile
    end
  end
end
