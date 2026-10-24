# frozen_string_literal: true

require "application_system_test_case"

# Asking the assistant in words: what it saves is on its card at once, and
# Undo takes it back. The model is stood in for (SavesATask): the tool it
# calls, the change set and the card are the app's own.
class AssistantTest < ApplicationSystemTestCase
  # Whatever it is asked, it saves a task for today through the add_task
  # tool, as the model would, and says so.
  class SavesATask < SimpleDelegator
    Llm = Struct.new(:messages, :result_callbacks) do
      def before_tool_call(&) = self
      def after_tool_result(&block) = result_callbacks << block
      def after_message(&) = self
      def cancel; end
    end

    def to_llm = @llm ||= Llm.new([], [])

    def complete
      result = Assistant::AddTaskTool.new(chat: __getobj__).call(title: "Repot the basil", date: Date.current.iso8601)
      to_llm.result_callbacks.each { |callback| callback.call(result) }
      yield RubyLLM::Chunk.new(role: :assistant, content: "Saved it.")
      assistant_messages.create!(role: "assistant", content: "Saved it.")
    end

    def add_message(role:, content:) = assistant_messages.create!(role: role.to_s, content: content)
  end

  test "asked in words, the assistant saves a task, shows it on its card, and Undo takes it back" do
    sign_in profiles(:alice)
    visit assistant_path
    click_on I18n.t("assistant.chats.new")

    fill_in I18n.t("assistant.composer.placeholder"), with: "Remind me to repot the basil today"
    assert_listening
    click_on I18n.t("assistant.composer.send")
    assert_text "Remind me to repot the basil today"

    # The reply runs after the response, as in production: the response puts
    # the question and the "replying" placeholder the reply streams before.
    swapping(Assistant::BookkeeperAgent, :for, ->(chat) { SavesATask.new(chat) }) { perform_enqueued_jobs(only: Assistant::ReplyJob) }
    assert_selector ".assistant-change-set", text: "Repot the basil"
    assert_text "Saved it."
    task = profiles(:alice).events.find_by!(title: "Repot the basil")
    assert_accessible "the assistant's card for what it saved"

    within(".assistant-change-set") { click_on I18n.t("assistant.change_sets.buttons.undo") }
    assert_selector ".assistant-change-set--undone"
    assert_not Event.exists?(task.id), "undone, the task is gone"
  end
end
