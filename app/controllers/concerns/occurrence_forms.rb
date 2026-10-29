# frozen_string_literal: true

# What a controller that opens and saves a day's form shares, whichever
# kind of series the day belongs to: the kind's form save
# (Occurrences::FormSave), what the form may send, the kind's form view and
# the answers. A controller names the kind (#event_class): a new series'
# controller its own, a day's the series'.
module OccurrenceForms
  extend ActiveSupport::Concern

  include LinkApprovable
  include Views::Calendar::DayPaths

  private

  def event_class = raise(NotImplementedError, "#{self.class.name}#event_class")
  def form_save = Occurrences::FormSave.for(event_class.name)

  # What the form sent, permitted here and nowhere else: the day's fields
  # under the kind's key, as its form declares them, the series' shape
  # under `event`, and the names of the fields typed in it. A form with a
  # cost section sends the cost under `transaction`, which is a payment's
  # own key, so only those forms read it.
  def form_params
    sent = {
      event: params.fetch(:event, {}).permit(*Occurrences::FormSave::SeriesShape::PARAMS).to_h,
      form_save.param_key => params.expect(form_save.param_key => form_save.permitted_fields).to_h,
      typed_fields: params[:typed_fields]
    }
    return sent unless form_save.cost?

    sent.merge(transaction: params.fetch(:transaction, {}).permit(*Occurrences::FormSave::COST_PARAMS).to_h)
  end

  def notice(key) = t("#{event_class.model_name.route_key}.notices.#{key}")

  def saved(key)
    render turbo_stream: [ close_modal, toast(:success, notice(key)) ]
  end

  # The form again, with what was wrong in it. The end is drawn as it was
  # sent: an end the series was refused never reached it, and its error is
  # said under the field it was typed in.
  def shown_again(occurrence)
    ends_sent = form_params[:event].slice(*Events::SeriesEnd::PARAMS)
    render turbo_stream: redraw_modal(form_of(occurrence, ends_sent: ends_sent)), status: :unprocessable_content
  end

  # The kind's form (Views::Occurrences::Forms) for the viewer, with their
  # own "remind me" rows on the series and whether those may come by email,
  # and the owner's housemates for a form that offers them (a payment's
  # other side).
  def form_of(occurrence, ends_sent: {})
    owner = occurrence.event.profile || current_profile
    Views::Occurrences::Forms.for(occurrence.event.class).new(
      occurrence: occurrence, url: form_url(occurrence), current_profile: current_profile,
      reminders: reminders_of(occurrence), reminder_mail: Emails.for_reminders(current_profile),
      housemates: owner.housemates.order(:username), ends_sent: ends_sent
    )
  end

  # Where the form is sent: a day of a series that exists to that day, a
  # new series to its kind.
  def form_url(occurrence)
    occurrence.event.persisted? ? day_path(occurrence) : polymorphic_path(occurrence.event.class)
  end

  # The viewer's own "remind me" rows on the series; a new series has none.
  def reminders_of(occurrence)
    occurrence.event.persisted? ? occurrence.event.reminders_of(current_profile).to_a : []
  end
end
