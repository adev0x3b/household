# frozen_string_literal: true

# Presses the chat's buttons the way the user would ("!confirm", "!undo" in a
# scenario), through the same code the controllers run.
module AssistantEval
  module Buttons
    module_function

    def press(action, chat)
      case action
      when "confirm" then confirm(chat)
      when "undo" then undo(chat)
      else raise ArgumentError, "unknown button #{action}"
      end
    end

    def confirm(chat)
      set = chat.change_sets.awaiting_confirmation.order(:id).last
      return "nothing to confirm" if set.nil?

      Assistant::ChangeSets::Applier.call(set, confirmed: true)
      "applied change set #{set.id}"
    end

    def undo(chat)
      set = chat.change_sets.applied.order(:id).last
      return "nothing to undo" if set.nil?

      Assistant::ChangeSets::Undoer.call(set)
      "undid change set #{set.id}"
    end
  end
end
