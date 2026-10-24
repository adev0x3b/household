# frozen_string_literal: true

# A lab report's day: its name, its values (analyte, value, unit — the
# day's own rows, flagged against the reference ranges once saved), notes,
# how it repeats and the therapy it belongs to.
class Views::LabTestResults::Modals::Form < Views::Occurrences::Form
  private

  # The values' rows want the room.
  def modal_size = :large

  def fields(f)
    render_text_field(f, :title, "lab_test_results.form.title_label", placeholder_key: "lab_test_results.form.title_placeholder", autofocus: true)
    render_entries_section
    render_text_area(f, :notes, "lab_test_results.form.notes_label", placeholder_key: "lab_test_results.form.notes_placeholder")
    render_event_fields
    render_collection_picker
    render_status_field(f)
  end

  def render_entries_section
    fieldset(class: "lab-entries") do
      legend(class: "label lab-entries__label") { t("lab_test_results.form.entries.label") }
      render_datalists

      render Components::NestedFields.new(rows_class: "lab-entries__rows", row_class: "lab-entry-row", prefix: method(:entry_field_prefix),
                                          add_label: t("lab_test_results.form.entries.add"), remove_label: t("lab_test_results.form.entries.remove"),
                                          errors: form_errors.rows(:lab_test_result_entries)) do |fields|
        fields.headings([ t("lab_test_results.form.entries.analyte_label"), "lab-entry-row__field" ],
                        [ t("lab_test_results.form.entries.value_label"), "lab-entry-row__field" ],
                        [ t("lab_test_results.form.entries.unit_label"), "lab-entry-row__field lab-entry-row__field--unit" ])
        fields.rows { existing_entries.each { |entry| render_entry_row(fields, entry, fields.index_of(entry)) } }
        fields.template { render_entry_row(fields, LabTestResultEntry.new, Components::NestedFields::NEW_ROW) }
      end
    end
  end

  # Rendered once (not per-row) — every analyte/unit input references these
  # by id via `list:`, letting the user pick a suggestion or type a new name
  # in the same field either way.
  def render_datalists
    datalist(id: "analytes-datalist") { Analyte.names_for(@current_profile).each { |name| option(value: name) } }
    render Components::UnitsDatalist.new(profile: @current_profile)
  end

  def existing_entries
    entries = @occurrence.lab_test_result_entries.to_a
    entries.any? ? entries : [ LabTestResultEntry.new ]
  end

  def entry_field_prefix(index)
    "#{param_key}[lab_test_result_entries_attributes][#{index}]"
  end

  def render_entry_row(fields, entry, index)
    fields.row(record: entry, index: index) do |prefix, row|
      div(class: "lab-entry-row__field") do
        input(type: "text", name: "#{prefix}[analyte_name]", value: entry.analyte&.name, list: "analytes-datalist", class: "input is-small",
              placeholder: t("lab_test_results.form.entries.analyte_placeholder"), aria: { label: t("lab_test_results.form.entries.analyte_label"), **row.aria(:analyte, :analyte_id) })
      end

      div(class: "lab-entry-row__field lab-entry-row__field--value") do
        input(type: "text", name: "#{prefix}[value]", value: entry.value, class: "input is-small",
              placeholder: t("lab_test_results.form.entries.value_placeholder"), aria: { label: t("lab_test_results.form.entries.value_label"), **row.aria(:value) })
        render_flag_badge(entry)
      end

      div(class: "lab-entry-row__field lab-entry-row__field--unit") do
        input(type: "text", name: "#{prefix}[unit_name]", value: entry.unit&.name, list: Components::UnitsDatalist::ID, class: "input is-small",
              placeholder: t("lab_test_results.form.entries.unit_placeholder"), aria: { label: t("lab_test_results.form.entries.unit_label"), **row.aria(:unit) })
      end
    end
  end

  def render_flag_badge(entry)
    flag = entry.persisted? ? entry.flag : nil
    return unless flag

    render Views::LabTestResults::FlagBadge.new(flag: flag)
  end
end
