# frozen_string_literal: true

# What a press on a change set card answers with, whichever controller
# took it: the set is found among the viewer's own, and once the press is
# done the outcome is noted for the model, so its next reply knows what
# the user did, and the card is drawn again with its toast.
module Assistant::ChangeSetAnswers
  extend ActiveSupport::Concern

  included do
    include AssistantEnabled

    before_action :set_change_set
  end

  private

  def set_change_set
    @change_set = policy_scope(Assistant::ChangeSet).find(params[:change_set_id] || params[:id])
  end

  # outcome: applied, failed, cancelled or undone, which names both the
  # toast and the note (app/prompts/assistant/notes/change_set_*).
  def finish(toast_kind, outcome)
    @change_set.chat.note_for_model!(Assistant::Notes.render(:"change_set_#{outcome}", id: @change_set.id))
    set = @change_set.reload
    card = Views::Assistant::Chats::ChangeSetCard.new(change_set: set, targets: Assistant::ChangeSets::RowTargets.load(set))
    render turbo_stream: [
      turbo_stream.replace(Views::Assistant::Chats::ChangeSetCard.dom_id(set), card),
      toast(toast_kind, t("assistant.change_sets.notices.#{outcome}"))
    ]
  end
end
