# frozen_string_literal: true

# A task's day: what to do, its priority, how it repeats, and, for a day
# of a series that exists, where it stands.
class Views::Tasks::Modals::Form < Views::Occurrences::Form
  private

  def fields(f)
    render_text_field(f, :title, "tasks.form.title_label", placeholder_key: "tasks.form.title_placeholder", autofocus: true)
    details_fields(f) { |d| render_details_select(d, :priority, "tasks.form.priority_label", priority_options) }
    render_text_area(f, :notes, "tasks.form.description_label", placeholder_key: "tasks.form.description_placeholder")
    render_event_fields
    render_collection_picker
    render_status_field(f)
  end

  def priority_options
    select_options(Task::Details.priorities.keys) { |key| t("tasks.priority.#{key}") }
  end
end
