# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # The fields of a record that is not a day of a series (a supply, a
      # recipe, a grocery list): written on the record itself.
      class RecordFields < Fields
        def check
          normalize!
          validate
        end

        def before = { before: changes.keys.to_h { |key| [ key, record.public_send(key).as_json ] } }

        def apply!(_applier)
          record.update!(changes)
          []
        end

        private

        # The changes checked as they would be saved, then put back.
        def validate
          record.assign_attributes(changes)
          record.validate
          record.errors.each { |error| problems << "#{error.attribute} #{error.message}" }
          record.restore_attributes
        end
      end
    end
  end
end
