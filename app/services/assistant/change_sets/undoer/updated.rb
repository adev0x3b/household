# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A record's fields as they were; a day with everything its update
      # touched (Operations::Update).
      class Updated < Step
        private

        def revert(updated) = updated.is_a?(Occurrence) ? undo_day(updated) : undo_record(updated)

        def undo_record(updated)
          authorize(updated, :update?)
          updated.update!(entry["before"])
          if entry["items_before"]
            updated.grocery_list_items.destroy_all
            entry["items_before"].each { |attrs| updated.grocery_list_items.create!(attrs) }
          end
          GroceryLists::Broadcaster.changed(updated) if updated.is_a?(GroceryList)
        end

        # A day as it was: its series' fields and details, its own override
        # row, its values or recipes, the slot it moved from. A day this set
        # saved goes back to unsaved.
        def undo_day(day)
          authorize(day, :update?)
          event = day.event
          refresh(event)
          day.uncomplete! if entry["completed"] && day.completed?
          restore_recipes(day, entry["recipes_before"]) if entry["recipes_before"]
          restore_lab_values(day, entry["lab_before"]) if entry["lab_before"]
          event.update!(entry["series_before"]) if entry["series_before"].present?
          event.details.update!(entry["series_details_before"]) if entry["series_details_before"].present?
          restore_own_details(day)
          restore_series(event, entry["event_before"]) if entry["event_before"]
          if entry["moved_from"]
            date, time = entry["moved_from"]
            event.unskip!(Date.iso8601(date), time: time)
          end
          restore_day(day)
        end

        # A meal's recipes as they were, on the details row the change wrote;
        # a done meal takes its ingredients again for exactly those.
        def restore_recipes(day, before)
          if before["row"] == "series"
            day.event.details.replace_recipes!(before["ids"])
          else
            day.own_details.replace_recipes!(before["ids"] || [])
          end
          Meal::Consumption.new(day.reload).resync! if day.completed?
        end

        def restore_lab_values(day, before)
          day.lab_test_result_entries.destroy_all
          before.each { |attrs| day.lab_test_result_entries.create!(attrs) }
        end

        def restore_own_details(day)
          if entry["details_created"]
            day.own_details.destroy!
          elsif entry["details_before"].present?
            day.own_details.update!(entry["details_before"])
          end
        end

        def restore_day(day)
          if entry["materialized"]
            day.reload.destroy!
          else
            day.reload.update!(entry["before"].to_h)
          end
        end
      end
    end
  end
end
