# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A record that is its name, kept in a catalog of the user's: a therapy,
    # an ingredient, a recipe, a grocery list. Found again by its name, and
    # saved with what it holds (a recipe's steps, a list's items) in one go.
    class NamedRecords < DraftBuilder
      # The user's records of the kind with the same name.
      def duplicates
        name = record.name.to_s.strip
        return [] if name.blank?

        resource.accessible(profile).where("LOWER(#{resource.model.quoted_table_name}.name) = ?", name.downcase)
          .map { |found| summarize(found) }
      end

      def save!(committer)
        Pundit.authorize(profile, record, :create?)
        record.save!
        committer.keep(record)
      end

      def label = record.name.presence || type_label
    end
  end
end
