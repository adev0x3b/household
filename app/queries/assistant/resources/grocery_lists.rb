# frozen_string_literal: true

module Assistant
  module Resources
    class GroceryLists < Resource
      def key = "grocery_list"
      def model = GroceryList
      def list_items? = true
      def search_columns = %i[name]
      def writable = %w[name status]
      def enums = { "status" => GroceryList.statuses.keys }
      def kind_words = %w[lista liste spesa list lists shopping grocery groceries]

      def scope(profile) = GroceryList.where(id: GroceryList.accessible_by(profile).select(:id))

      # "The list" is the one being shopped for; with several in use, the
      # model is asked which.
      def in_use? = true
      def in_use(profile) = accessible(profile).active.reorder(updated_at: :desc, id: :desc)

      def summaries(lists, _profile)
        lists.map do |list|
          { name: list.name, status: list.status,
            items: list.grocery_list_items.map { |item| "#{item.checked? ? "[x]" : "[ ]"} #{pantry_line(item)}" } }
        end
      end

      private

      def read_for_summaries(lists)
        super
        load(lists, grocery_list_items: %i[ingredient unit])
      end
    end
  end
end
