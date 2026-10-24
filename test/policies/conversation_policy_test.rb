# frozen_string_literal: true

require "test_helper"

class ConversationPolicyTest < ActiveSupport::TestCase
  test "a conversation is for the people in it; the household's can be renamed by any of them" do
    chat = Conversation.household_conversation(households(:example))
    direct = Conversation.direct_between(profiles(:alice), profiles(:bob))

    assert_predicate ConversationPolicy.new(profiles(:carol), chat), :show?
    assert_predicate ConversationPolicy.new(profiles(:carol), chat), :update?
    assert_not ConversationPolicy.new(profiles(:outsider), chat).show?

    assert_predicate ConversationPolicy.new(profiles(:bob), direct), :show?
    assert_not ConversationPolicy.new(profiles(:bob), direct).update?
    assert_not ConversationPolicy.new(profiles(:carol), direct).show?
    assert_not ConversationPolicy.new(profiles(:carol), direct).read?
    assert_equal [ chat, direct ].sort_by(&:id), ConversationPolicy::Scope.new(profiles(:alice), Conversation).resolve.order(:id).to_a
    assert_equal [ chat ], ConversationPolicy::Scope.new(profiles(:carol), Conversation).resolve.to_a
  end

  test "a message can be sent by those in the conversation and unsent by its sender alone" do
    direct = Conversation.direct_between(profiles(:alice), profiles(:bob))
    message = send_message(direct, profiles(:alice))

    assert_predicate MessagePolicy.new(profiles(:bob), direct.messages.new), :create?
    assert_not MessagePolicy.new(profiles(:carol), direct.messages.new).create?
    assert_predicate MessagePolicy.new(profiles(:alice), message), :destroy?
    assert_not MessagePolicy.new(profiles(:bob), message).destroy?
    assert_predicate MessagePolicy.new(profiles(:bob), message), :react?
    assert_not MessagePolicy.new(profiles(:carol), message).react?

    message.unsend!
    assert_not MessagePolicy.new(profiles(:alice), message).destroy?
    assert_not MessagePolicy.new(profiles(:bob), message).react?
  end

  test "pictures go with a message where the installation has them on" do
    direct = Conversation.direct_between(profiles(:alice), profiles(:bob))

    assert_predicate MessagePolicy.new(profiles(:bob), direct.messages.new), :attach?
    assert_not MessagePolicy.new(profiles(:carol), direct.messages.new).attach?
    with_env("PICTURES" => "off") { assert_not MessagePolicy.new(profiles(:bob), direct.messages.new).attach? }
  end
end
