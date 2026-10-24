# frozen_string_literal: true

# A day of a series in its form: a modal for the day — an Occurrence,
# saved or projected — holding a Views::Occurrences::DayForm that posts
# under the kind's params key (`task[...]`) what Occurrences::FormSave
# reads: the day's fields as the day reads them (its own, else the
# series'), the kind's own under `details_attributes` (the day's details:
# its override row, else the series'), and `event[...]` for the series
# (its rule, slots, collection, the viewer's reminders).
#
# Each kind's form (Views::<Kinds>::Modals::Form) inherits it and draws
# its fields in the order every kind keeps (`fields`); the modal, its
# words, the hidden fields that say which day and the shared field shapes
# are drawn here. Every form takes the same inputs, so whoever opens one
# needs to know nothing of the kind: the day, where the form is sent, the
# viewer, the viewer's own "remind me" rows on the series (none on a new
# one) and the owner's housemates, for a form that offers them (a
# payment's other side).
class Views::Occurrences::Form < Views::Base
  # The form for a day the assistant drafted: a new series of the kind,
  # posting to the kind's create route, for the viewer.
  def self.draft(occurrence, viewer:, housemates: [])
    url = Rails.application.routes.url_helpers.polymorphic_path(occurrence.event.class)
    new(occurrence: occurrence, url: url, current_profile: viewer, housemates: housemates)
  end

  def initialize(occurrence:, url:, current_profile:, reminders: [], housemates: [])
    @occurrence = occurrence
    @url = url
    @current_profile = current_profile
    @reminders = reminders
    @housemates = housemates
  end

  def view_template
    render Components::Modal.new(size: modal_size, section: @occurrence.section) do |modal|
      modal.modal_header(title: modal_title, subtitle: modal_subtitle, icon: Views::Calendar::Cards.icon_of(event))

      render Views::Occurrences::DayForm.new(record: @occurrence, viewer: @current_profile, url: @url, submit_text: submit_text,
                                             modal: modal, form_data: form_data) do |f|
        render_hidden_fields(f)
        fields(f)
      end
    end
  end

  private

  # The kind's fields, in the order every kind keeps, so a person moving
  # between kinds finds each thing where they found it last: the title,
  # the kind's own fields and lists, notes, how it repeats (and a dose's
  # times), the collection, the cost, and the status last.
  def fields(_f) = raise(NotImplementedError, "#{self.class.name}#fields")

  # A kind whose form has more to show asks for a wider modal.
  def modal_size = :medium

  # The data of the kind's own Stimulus controller, joined to the form's.
  def form_data = {}

  def event = @occurrence.event
  def details = @occurrence.details
  def param_key = event.class.model_name.param_key
  def i18n_scope = event.class.model_name.route_key

  # An existing series (a saved day of it, or one still projected) rather
  # than a new one.
  def editing? = event.persisted?

  # A day of a repeating series, saved to the day alone or to the whole
  # series (Views::Occurrences::DayForm's "apply to").
  def apply_to? = editing? && event.recurring?

  def modal_title = t("#{i18n_scope}.form.#{editing? ? "edit_title" : "new_title"}")
  # The day being changed; a new series has nothing to name yet.
  def modal_subtitle = (l(@occurrence.date, format: :long) if editing?)
  def submit_text = t("#{i18n_scope}.form.#{editing? ? "update" : "create"}")

  # A new series' first day; a day of a series that exists is named by the
  # form's address.
  def render_hidden_fields(f)
    f.hidden_field :date, value: @occurrence.date&.iso8601 unless editing?
  end

  # The series' repeat rule and the viewer's own "Remind me" rows.
  def render_event_fields
    render Views::Occurrences::EventFields.new(event: event)
    render Views::Occurrences::ReminderFields.new(reminders: @reminders)
  end

  def render_collection_picker
    render Views::Occurrences::CollectionPicker.new(event: event, profile: @current_profile, section: @occurrence.section)
  end

  # A field of the day (its own value, else the series'); required when
  # the series requires it.
  def render_text_field(f, attribute, label_key, placeholder_key: nil, autofocus: false, type: :text_field, data: {})
    form_field(f, attribute, label: t(label_key), record: event) do |field|
      f.public_send(type, attribute,
                    class: "input is-medium",
                    placeholder: (t(placeholder_key) if placeholder_key),
                    autofocus: autofocus,
                    required: required_attribute?(event, attribute),
                    data: data, aria: field.aria)
    end
  end

  def render_text_area(f, attribute, label_key, placeholder_key: nil, rows: 3)
    form_field(f, attribute, label: t(label_key), record: event) do |field|
      f.text_area attribute, class: "textarea", placeholder: (t(placeholder_key) if placeholder_key), rows: rows, aria: field.aria
    end
  end

  # A wall-clock time ("11:00"), as the day reads it.
  def render_time_field(f, attribute, label_key)
    form_field(f, attribute, label: t(label_key), record: event) do |field|
      f.time_field attribute, class: "input is-medium", value: @occurrence.public_send(attribute)&.strftime("%H:%M"), aria: field.aria
    end
  end

  # One of the kind's own fields, a choice among its enum's values;
  # `required: false` for one only some of its kinds need (an injection's side).
  # `selected:` when the day shows another value than its details hold (a
  # projected injection's alternated side).
  def render_details_select(d, attribute, label_key, options, include_blank: nil, data: {}, wrapper_data: {}, required: true, selected: nil)
    required &&= required_attribute?(details, attribute)
    form_field(d, attribute, label: t(label_key), record: details, required: required, select: true, data: wrapper_data) do |field|
      d.select attribute, options, { include_blank: include_blank, selected: selected }.compact, data: data, required: required, aria: field.aria
    end
  end

  # The kind's own fields, posted as `details_attributes`: written on the
  # series' row, or on the day's own when the day alone changes.
  def details_fields(f, &)
    f.fields_for(:details_attributes, details, &)
  end

  # The day's form draws its kind's fields from the details, but a failed
  # save keeps their errors on the day, which the form may have rebuilt
  # from what was sent.
  def field_errors(f, attribute)
    return super unless f.object.equal?(details)

    form_errors.for(:"details.#{attribute}")
  end

  def form_errors = @form_errors ||= Forms::Errors.new(@occurrence)

  # Where the day is in its lifecycle, once saved: the statuses its kind allows.
  def render_status_field(f, data: {})
    return unless @occurrence.persisted?

    render Components::Field.new(label: t("#{i18n_scope}.form.status_label"), control_id: "#{param_key}_status", select: true) do
      f.select :status, status_options, {}, data: data
    end
  end

  def status_options
    event.class.allowed_statuses.map { |status| [ t("#{i18n_scope}.status.#{status}"), status ] }
  end
end
