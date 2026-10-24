# frozen_string_literal: true

module GroceryLists
  # Pushes a list's live regions to everyone who can see it, over the
  # per-viewer signed stream the list page opens with
  # `turbo_stream_from list, profile` (Views::GroceryLists::Show), and its
  # card on the lists page over their notifications stream, which every
  # page opens. Called by the controllers and the assistant's write paths
  # right after a change; whoever made the change also gets the same
  # regions in the response, so receiving them twice is harmless.
  #
  # DOM contract (see Views::GroceryLists::Show):
  #   #grocery_list-<id>-header   name, status, progress, sharing
  #   #grocery_list-<id>-items    the sections to buy, the basket, "Finish shopping"
  #   #grocery_list-<id>-page     the whole page (replaced when the list is deleted)
  #   #grocery_list_<id>          its card on the lists page (Views::GroceryLists::Card)
  class Broadcaster < ApplicationBroadcaster
    def self.changed(grocery_list)
      quietly do
        list = GroceryList.with_everything.find(grocery_list.id)
        list.people_with_access.each do |profile|
          as(profile) do
            stream_to([ list, profile ], :replace, Views::GroceryLists::Header.new(grocery_list: list, viewer: profile),
                      target: Views::GroceryLists::Header.dom_id(list))
            stream_to([ list, profile ], :replace, Views::GroceryLists::Items.new(grocery_list: list), target: Views::GroceryLists::Items.dom_id(list))
            stream_to([ profile, :notifications ], :replace, Views::GroceryLists::Card.new(grocery_list: list, viewer: profile),
                      target: Views::GroceryLists::Card.dom_id(list))
          end
        end
      end
    end

    # The list is gone: whoever still has its page open is told, where the
    # list was, and its card leaves their lists page.
    def self.destroyed(grocery_list, viewers)
      quietly do
        viewers.each do |profile|
          as(profile) { stream_to([ grocery_list, profile ], :replace, Views::GroceryLists::Gone.new, target: Views::GroceryLists::Show.dom_id(grocery_list)) }
          stream_to([ profile, :notifications ], :remove, target: Views::GroceryLists::Card.dom_id(grocery_list))
        end
      end
    end
  end
end
