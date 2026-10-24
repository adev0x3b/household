# frozen_string_literal: true

# What a kind of series' controller (TasksController, MedicationsController,
# …) does: the form for a new series of its kind, on the day the "+" was
# pressed, and its creation, on one's own calendar or a linked housemate's
# who lets one add that kind, or asks first (`owner_id`, from
# Links::Permissions#creatable_owners). Each kind names itself
# (#event_class) and overrides what differs. A day of a series, once it
# exists, is DaysController's, whatever its kind.
class SeriesController < ApplicationController
  include OccurrenceForms

  def new
    occurrence = new_occurrence
    authorize occurrence, :new?

    render_modal(form_of(occurrence), page: calendar_path)
  end

  def create
    form = form_save.new(actor: current_profile, owner: requested_owner, params: form_params)
    authorize form.record, form.policy_query
    return if held_for_approval?(form.record, form.policy_query, kind: :create, form: form)

    if form.save
      after_save(form)
      saved(:created)
    else
      shown_again(form.record)
    end
  end

  private

  # A new series' first day, on the day its "+" was pressed (today without one).
  def new_occurrence
    event_class.new(profile: current_profile).occurrence_on(requested_date || Date.current)
  end

  def requested_date
    Date.iso8601(params[:date].to_s) if params[:date].present?
  rescue Date::Error
    nil
  end

  # Whose calendar a new series goes on: one's own, or a linked housemate's
  # who lets one add (or ask to add) that kind.
  def requested_owner
    return current_profile if params[:owner_id].blank? || params[:owner_id].to_s == current_profile.id.to_s

    owners = Links::Permissions.for(current_profile).creatable_owners(event_class.name)
    owners.find { |owner| owner.id.to_s == params[:owner_id].to_s } ||
      raise(Pundit::NotAuthorizedError, "not a calendar one can add to")
  end

  # What a kind does once its new series is saved (nothing by default).
  def after_save(_form); end
end
