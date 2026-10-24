# frozen_string_literal: true

# Puts a series in one of the viewer's collections of its section, such as a
# therapy in Healthcare (collections.sections.<section>.picker). Renders under
# the `event[...]` params namespace, same as Views::Occurrences::EventFields,
# since the collection is the series' (Event#collection), not the day's;
# Occurrences::FormSave re-checks it against what the people can reach.
#
#   render Views::Occurrences::CollectionPicker.new(event: occurrence.event, profile: current_profile, section: occurrence.section)
class Views::Occurrences::CollectionPicker < Views::Base
  def initialize(event:, profile:, section:)
    @event = event
    @profile = profile
    @section = section.to_s
  end

  # Nothing when the series is in a collection the viewer can't reach (a
  # series shared on its own): the form then leaves it where it is.
  def view_template
    collections = Collection.choices_for(@profile, section: @section, current_id: selected_id)
    return if collections.nil?

    render Components::Field.new(label: t("collections.sections.#{@section}.picker.label"), control_id: "event_collection_id",
                                 select: true, class: "collection-picker") do
      select(name: "event[collection_id]", id: "event_collection_id") do
        option(value: "", selected: selected_id.blank?) { t("collections.sections.#{@section}.picker.none") }

        collections.each do |collection|
          option(value: collection.id, selected: selected_id == collection.id) { collection.name }
        end
      end
    end
  end

  private

  def selected_id
    @event&.collection_id
  end
end
