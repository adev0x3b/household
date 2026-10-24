# frozen_string_literal: true

# A dose: the medication, its kind (an injection's area and side), what it
# uses from the supply cupboard, notes, how it repeats and at what times of
# the day, the therapy it belongs to and — once saved — whether it was
# taken, when, or why not.
class Views::Medications::Modals::Form < Views::Occurrences::Form
  private

  def form_data = { controller: "medication-form" }

  def fields(f)
    render_text_field(f, :title, "medications.form.name_label", placeholder_key: "medications.form.name_placeholder", autofocus: true)
    details_fields(f) do |d|
      render_details_select(d, :kind, "medications.form.kind_label", select_options(Medication::Details.kinds.keys) { |key| t("medications.kind.#{key}") },
                            data: { medication_form_target: "kind", action: "change->medication-form#syncKind" })
      render_details_select(d, :area, "medications.form.area_label", select_options(Medication::Details.areas.keys) { |key| t("medications.area.#{key}") },
                            data: { medication_form_target: "areaSelect" }, wrapper_data: { medication_form_target: "areaSection" }, required: false)
      render_details_select(d, :side, "medications.form.side_label", select_options(Medication::Details.sides.keys) { |key| t("medications.side.#{key}") },
                            data: { medication_form_target: "sideSelect" }, wrapper_data: { medication_form_target: "sideSection" }, required: false,
                            selected: projected_side)
    end
    render_supply_uses_section
    render_text_area(f, :notes, "medications.form.notes_label", placeholder_key: "medications.form.notes_placeholder")
    render_event_fields
    # The times go in whenever the series is there: a new one whose save
    # failed still carries the ones the form sent.
    render Views::Medications::DoseTimesFields.new(event: event)
    render_collection_picker
    return unless @occurrence.persisted?

    render_status_field(f, data: { medication_form_target: "status", action: "change->medication-form#syncStatus" })
    render_skipped_reason_field(f)
    render_taken_at_field(f)
  end

  # A dose not saved yet would be injected on the other side from the last
  # one (Medication#projected_side_for); a saved one says where it was.
  def projected_side
    return unless editing? && !@occurrence.persisted? && details.injection?

    event.projected_side_for(@occurrence)&.to_s
  end

  def uses_prefix(index) = "#{param_key}[details_attributes][supply_uses_attributes][#{index}]"

  # What a dose uses besides the drug itself, if anything: a syringe, a wipe.
  def render_supply_uses_section
    list = ::Occurrences::DetailsList.new(@occurrence, :supply_uses, key: :supply_id, prefix: method(:uses_prefix))

    fieldset(class: "supply-consumptions") do
      legend(class: "label") { t("medications.form.supply_uses.label") }
      p(class: "help") { t("medications.form.supply_uses.help") }
      list.dropped_inputs.each { input(**_1) }

      render Components::NestedFields.new(rows_class: "supply-consumptions__rows", row_class: "supply-consumption-row", prefix: method(:uses_prefix),
                                          add_label: t("medications.form.supply_uses.add"), remove_label: t("medications.form.supply_uses.remove"),
                                          errors: form_errors.rows(:"details.supply_uses")) do |fields|
        fields.rows { list.rows.each { |row| render_use_row(fields, row.child, row.index, id_inputs: list.id_inputs(row)) } }
        fields.template { render_use_row(fields, SupplyUse.new, Components::NestedFields::NEW_ROW) }
      end
    end
  end

  def render_use_row(fields, use, index, id_inputs: nil)
    fields.row(record: use, index: index, id_inputs: id_inputs) do |prefix, row|
      div(class: "supply-consumption-row__field") do
        div(class: "select is-small is-fullwidth") do
          select(name: "#{prefix}[supply_id]", aria: { label: t("medications.form.supply_uses.supply_placeholder"), **row.aria(:supply, :supply_id) }) do
            option(value: "") { t("medications.form.supply_uses.supply_placeholder") }
            render_supply_optgroups(use)
          end
        end
      end

      div(class: "supply-consumption-row__field supply-consumption-row__field--quantity") do
        input(type: "number", step: "any", min: "0", name: "#{prefix}[quantity]", value: number_value(use.quantity), class: "input is-small",
              placeholder: t("medications.form.supply_uses.quantity_placeholder"), aria: { label: t("medications.form.supply_uses.quantity_label"), **row.aria(:quantity) })
      end
    end
  end

  # Groups the picker by Supply#category (Medication vs. Consumable) so
  # picking "the drug itself" is visually distinct from picking an
  # ancillary item (syringe, wipe…) in the one shared list.
  def render_supply_optgroups(use)
    Supply.categories.each_key do |category|
      supplies = supplies_by_category[category]
      next if supplies.blank?

      optgroup(label: t("supplies.category.#{category}")) do
        supplies.each do |supply|
          option(value: supply.id, selected: use.supply_id == supply.id) { supply.name }
        end
      end
    end
  end

  # The dose's owner's supplies (a dose shared with the viewer draws from
  # the owner's stock — SupplyUse validates the same).
  def supplies_by_category
    owner = event.profile || @current_profile
    @supplies_by_category ||= Supply.choices_for(owner).group_by(&:category)
  end

  # Why a skipped dose wasn't taken (shown with "Skipped").
  def render_skipped_reason_field(f)
    render Components::Field.new(label: t("medications.form.skipped_reason_label"), control_id: "#{param_key}_skipped_reason",
                                 select: true, data: { medication_form_target: "reasonSection" }) do
      f.select :skipped_reason, Medication.skip_reasons.map { |reason| [ t("medications.skipped_reason.#{reason}"), reason ] },
               { include_blank: t("medications.form.skipped_reason_placeholder") },
               data: { medication_form_target: "reasonSelect" }
    end
  end

  # When a taken dose was really taken (its status shown as "Taken"), on the
  # viewer's clock.
  def render_taken_at_field(f)
    taken_at = @occurrence.completed_at&.in_time_zone
    render Components::Field.new(label: t("medications.form.taken_at_label"), control_id: "#{param_key}_completed_at",
                                 data: { medication_form_target: "takenAtSection" }) do
      f.datetime_local_field :completed_at, class: "input is-medium", value: taken_at&.strftime("%Y-%m-%dT%H:%M"),
                                            data: { medication_form_target: "takenAtInput" }
    end
  end
end
