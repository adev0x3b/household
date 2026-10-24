# frozen_string_literal: true

require "test_helper"

class Profiles::JoinTest < ActiveSupport::TestCase
  setup do
    @erin = Profile.create!(household: households(:example), username: "erin", email: "erin@example.com", password: "a-long-password")
    @chat = conversations(:example_chat)
  end

  test "whoever joins has the standard analytes and a place in the household's conversation" do
    assert_empty @erin.analytes
    assert_not @chat.participant?(@erin)

    assert_equal @erin, Profiles::Join.call(@erin)

    assert_equal Analyte::STANDARD_NAMES.sort, @erin.analytes.pluck(:name).sort
    assert @chat.reload.participant?(@erin)
  end

  test "joining again changes nothing" do
    Profiles::Join.call(@erin)

    assert_no_difference -> { Analyte.count + ConversationParticipant.count } do
      Profiles::Join.call(@erin)
    end
  end

  test "an invitation still waiting hasn't joined" do
    invited = Profile.invite!({ email: "finn@example.com", household: households(:example) }, profiles(:alice)) { _1.skip_invitation = true }

    assert_raises(ArgumentError) { Profiles::Join.call(invited) }
    assert_not @chat.reload.participant?(invited)
  end
end
