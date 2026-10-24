# frozen_string_literal: true

class TransactionsController < SeriesController
  private

  def event_class = Transaction

  # A new payment, possibly about something ("Add a cost" on a lab result's
  # card: `about_type` / `about_id`), kept by the form's hidden fields. The
  # series' row names a series or a purchase, so a day's cost is about that
  # day's series, on that day (Costable#costs).
  def new_occurrence
    about = about_from_params
    return super unless about

    date = requested_date || (about.date if about.is_a?(Occurrence)) || Date.current
    event_class.new(profile: current_profile).occurrence_on(date).tap do |occurrence|
      occurrence.event.details.about = about.is_a?(Occurrence) ? about.event : about
    end
  end

  # What `about_type` / `about_id` name, when the viewer can reach it and it
  # takes costs; nothing otherwise.
  def about_from_params
    scope = case params[:about_type]
    when "Occurrence" then Occurrence.accessible_by(current_profile)
    when "SupplyPurchase" then SupplyPurchase.accessible_by(current_profile)
    when "IngredientPurchase" then IngredientPurchase.accessible_by(current_profile)
    end
    about = scope&.find_by(id: params[:about_id])
    about if about&.costable?
  end

  # A payment about something is its cost (Costable#costs): its day is
  # stored, as Transactions::SetCost stores a fee's.
  def after_save(form)
    return if form.record.persisted? || form.event.details.about.nil?

    form.record.materialize!
    Calendar::DayCardBroadcaster.call(event: form.event)
  end
end
