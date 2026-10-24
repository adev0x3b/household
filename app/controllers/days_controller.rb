# frozen_string_literal: true

# A day of a series, saved or not yet: its form, its save and its deletion
# (one dose of it, the day, or `scope=series` the whole series, through
# Occurrences::Destroy), the same for every kind through the kind's form and
# form save. A linked housemate's day opens like one's own: read-only where
# the owner's grant doesn't let them change it, and held for the owner's
# OK where it says to ask (LinkApprovable).
class DaysController < ApplicationController
  include DayLookup
  include OccurrenceForms

  def edit
    authorize day, :show?

    render_modal(form_of(day), page: calendar_path(month: requested_date.month, year: requested_date.year))
  end

  def update
    authorize day
    form = form_save.new(actor: current_profile, params: form_params, record: day)
    return if held_for_approval?(day, :update?, kind: :update, form: form)

    if form.save
      saved(:updated)
    else
      shown_again(form.record)
    end
  end

  def destroy
    raise ActiveRecord::RecordNotFound unless day.persisted? || scheduled?(day)

    scope = params[:scope].presence_in(Occurrences::Destroy::SCOPES) || "occurrence"
    authorize day
    return if held_for_approval?(day, :destroy?, kind: :destroy, scope: scope)

    gone = Occurrences::Destroy.call(day, by: current_profile, scope: scope)
    render turbo_stream: toast(:success, t("calendar.occurrences.notices.#{gone}"))
  end

  private

  def event_class = event.class

  # A day nothing was stored about exists only where the series puts one.
  def scheduled?(occurrence)
    occurrence.event.occurrences_between(occurrence.date, occurrence.date).any? { |scheduled| scheduled.key == occurrence.key }
  end
end
