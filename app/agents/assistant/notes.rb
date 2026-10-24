# frozen_string_literal: true

# What the app tells the model, outside the agent's instructions, about
# something that happened on its turn: a reply that has to be tried again,
# a photo read, a tool call that keeps failing. The words are in
# app/prompts/assistant/notes, one template per note, beside the
# instructions; the code only says which note and fills in its blanks.
module Assistant
  module Notes
    def self.render(name, **locals) = RubyLLM.render_prompt("assistant/notes/#{name}", **locals).strip
  end
end
