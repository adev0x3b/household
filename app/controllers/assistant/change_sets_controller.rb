# frozen_string_literal: true

# A change set itself: reviewing a draft in it, and dropping one still in
# progress (Cancel on the card). Applying and undoing one is its
# application's (Assistant::ChangeSetApplicationsController).
class Assistant::ChangeSetsController < ApplicationController
  include Assistant::ChangeSetAnswers

  # A set still in progress has no records to edit yet, so its row opens the
  # create modal of its draft, filled in.
  def review
    authorize @change_set
    record = Assistant::ChangeSets::Review.draft_record(@change_set, params[:draft].to_i)
    return refuse(t("assistant.change_sets.notices.review_unavailable")) unless record

    render_modal(draft_form(record), page: @change_set.chat)
  end

  # The set stays, cancelled, as the record of what the assistant proposed.
  def destroy
    authorize @change_set, :cancel?
    @change_set.update!(status: :cancelled)
    finish(:success, :cancelled)
  end

  private

  # A draft opens the form of its kind (a day, its series' kind's), which
  # builds itself for the viewer (.draft).
  def draft_form(record)
    kind = record.is_a?(Occurrence) ? record.event.class : record.class
    Views::Occurrences::Forms.for(kind).draft(record, viewer: current_profile, housemates: other_profiles)
  end

  def other_profiles = current_profile.housemates.order(:username)
end
