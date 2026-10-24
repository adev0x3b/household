# frozen_string_literal: true

# An appointment's day: its kind (a visit, an interview, dinner with
# friends), who it's with — worded by the kind ("Provider" for a visit,
# "With" otherwise; appointment_form_controller.js follows a change) —
# when and where, how it repeats, the collection it belongs to, and what
# it cost.
class Views::Appointments::Modals::Form < Views::Occurrences::Form
  private

  def form_data = { controller: "appointment-form" }

  def fields(f)
    render_text_field(f, :title, "appointments.form.title_label", placeholder_key: kind.placeholder_key(:title), autofocus: true,
                                                                  data: { appointment_form_target: "titleInput" })
    details_fields(f) do |d|
      render_kind_field(d)
      render_counterpart_field(d)
    end
    render_time_field(f, :start_time, "appointments.form.start_time_label")
    render_text_field(f, :location, "appointments.form.location_label", placeholder_key: kind.placeholder_key(:location),
                                                                        data: { appointment_form_target: "locationInput" })
    render_text_area(f, :notes, "appointments.form.notes_label", placeholder_key: "appointments.form.notes_placeholder")
    render_event_fields
    render_collection_picker
    render_cost_section
    render_status_field(f)
  end

  def kind = details.kind_object

  # Each option carries its kind's wording: who it's with, and what its
  # title and place look like (appointment_form_controller.js swaps them in).
  def render_kind_field(d)
    form_field(d, :kind, label: t("appointments.form.kind_label"), record: details, select: true) do |field|
      select(name: "#{param_key}[details_attributes][kind]", id: "#{param_key}_details_attributes_kind",
             data: { appointment_form_target: "kind", action: "change->appointment-form#syncKind" }, aria: field.aria) do
        Appointment::Kind.all.each do |option_kind|
          option(value: option_kind.name, selected: option_kind == kind,
                 data: { label: t("#{option_kind.counterpart_label_key}.label"), placeholder: t("#{option_kind.counterpart_label_key}.placeholder"),
                         title_placeholder: t(option_kind.placeholder_key(:title)), location_placeholder: t(option_kind.placeholder_key(:location)) }) do
            option_kind.label
          end
        end
      end
    end
  end

  def render_counterpart_field(d)
    form_field(d, :counterpart, label: t("#{kind.counterpart_label_key}.label"), required: false,
                                label_data: { appointment_form_target: "counterpartLabel" }) do |field|
      d.text_field :counterpart, class: "input is-medium", placeholder: t("#{kind.counterpart_label_key}.placeholder"),
                                 data: { appointment_form_target: "counterpartInput" }, aria: field.aria
    end
  end

  # What it cost (amount and payment method): filed as its kind's fee and
  # named after who it was with.
  def render_cost_section
    fieldset do
      legend(class: "label") { t("appointments.form.cost_section.label") }
      p(class: "help") { t("appointments.form.cost_section.help") }

      render Views::Transactions::CostFields.new(cost: @occurrence.cost&.details, currency: @current_profile.household.currency)
    end
  end
end
