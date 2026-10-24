# frozen_string_literal: true

# The household bookkeeper: the model, tools and instructions of a chat turn.
# Its instructions (the static rules, then Assistant::Context) are never saved
# with the chat, so editing the rules never rewrites history.
module Assistant
  class BookkeeperAgent < RubyLLM::Agent
    # Reads, then one typed tool per kind of change (Assistant::ChangeTool).
    TOOLS = [ SearchRecordsTool, GetRecordTool,
              RecordLabResultsTool, SetReferenceRangesTool, RecordPurchasesTool, BookAppointmentTool,
              RecordPaymentTool, AddTaskTool, RecordMedicationTool, SetDoseSuppliesTool, AddCollectionTool,
              RecordGroceriesTool, AddIngredientTool, AddRecipeTool, AddGroceryListTool, PlanMealsTool,
              UpdateRecordTool, MarkDoneTool, DeleteRecordsTool, ShareTool ].freeze

    # The tool called by that name, nil for a name no longer in the list.
    def self.tool_named(name) = TOOLS.find { |tool| tool.tool_name == name.to_s }

    chat_model "Assistant::Chat"
    # The model and its tuning are read from the settings of the moment by
    # ::for, for each chat. Declared here, they would be read once at boot.
    model(assume_model_exists: true) { Assistant.model }

    tools { TOOLS.map { |tool| tool.new(chat: chat) } }

    instructions persist: false
    instructions(append: true, persist: false) { Assistant::Context.new(chat).to_prompt if chat.is_a?(Assistant::Chat) }

    # The chat record, moved to the current model (Chat#follow_settings!)
    # and tuned with today's settings, ready for a reply.
    def self.for(chat)
      chat.follow_settings!
      record = find(chat.id)
      llm = record.to_llm
      llm.with_temperature(Assistant.temperature) if Assistant.temperature
      llm.with_max_output_tokens(Assistant.max_output_tokens)
      llm.with_thinking(effort: Assistant.thinking_effort) if Assistant.thinking_effort
      record
    end
  end
end
