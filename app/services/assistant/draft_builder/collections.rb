# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A collection of series: a therapy (Healthcare's word for one) unless
    # the draft says which section it belongs to.
    class Collections < NamedRecords
      def label = record.name.to_s

      private

      def build
        Collection.new(writable_attributes.slice("name", "notes", "section").merge("profile" => profile)).tap do |collection|
          collection.section = "healthcare" unless Collection::SECTIONS.include?(collection.section)
        end
      end
    end
  end
end
