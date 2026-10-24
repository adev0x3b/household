# frozen_string_literal: true

# A change set's application: Apply on the card puts it there, for a set
# waiting on the button (a deletion, a possible duplicate, a change someone
# else will see), and Undo takes it away from a set that was saved,
# reverting what it wrote.
class Assistant::ChangeSetApplicationsController < ApplicationController
  include Assistant::ChangeSetAnswers

  def create
    authorize @change_set, :apply?
    Assistant::ChangeSets::Applier.call(@change_set, confirmed: true)
    finish(:success, :applied)
  rescue Assistant::ChangeSets::Applier::NotReady
    finish(:alert, :failed)
  # A set whose checks passed and whose save then failed points at a check
  # that let something through, more likely than at a race, so it is
  # reported as well as answered.
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    Rails.error.report(e, handled: true, context: { change_set_id: @change_set.id })
    finish(:alert, :failed)
  end

  def destroy
    authorize @change_set, :undo?
    Assistant::ChangeSets::Undoer.call(@change_set)
    finish(:success, :undone)
  rescue Assistant::ChangeSets::Undoer::CannotUndo => e
    refuse(t("assistant.change_sets.cannot_undo.#{e.key}", thing: e.thing))
  end
end
