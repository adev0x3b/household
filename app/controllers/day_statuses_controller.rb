# frozen_string_literal: true

# A day's status, from the "more" menu on its card: skipped, cancelled, or
# back to pending. The press is the status field of the day's form sent
# alone, so it is saved, and held for the owner's OK where their grant says
# to ask (LinkApprovable), exactly as the form would. Done and not done stay
# the circle's (DayCompletionsController).
class DayStatusesController < ApplicationController
  include DayLookup
  include LinkApprovable

  STATUSES = %w[skipped cancelled pending].freeze

  def update
    authorize day, :change_status?
    status = params[:status].to_s.presence_in(STATUSES) or return refuse(t("refusals.unknown_choice"))
    form = Occurrences::FormSave.for(event.type).new(actor: current_profile, record: day,
                                                     params: { event.class.model_name.param_key => { status: status } })
    return if held_for_approval?(day, :change_status?, kind: :update, form: form)

    if form.save
      render turbo_stream: toast(:success, t("calendar.occurrences.notices.status.#{status}"))
    else
      shown_again(form.record)
    end
  end

  private

  # A press has no form to draw again: what stopped it is said where the
  # person stands.
  def shown_again(occurrence)
    refuse(occurrence.errors.full_messages.to_sentence)
  end
end
