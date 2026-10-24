# frozen_string_literal: true

# The index's results frame, rendered by the full-page index, on its own as
# the answer to the navbar search (Components::IndexSearch), and whole again
# after a list is created, changed or deleted. The lists being shopped come
# first, all of them; the finished ones wait, folded away, newest on top and
# a page at a time, since they only ever grow.
class Views::GroceryLists::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "grocery_lists_results"
  FINISHED_PAGE = :finished_page

  # finished: a page of the finished lists (will_paginate).
  def initialize(shopping:, finished:, viewer:, query: nil)
    @shopping = shopping
    @finished = finished
    @viewer = viewer
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "grocery-lists__list", id: "grocery_lists_list") do
        if @shopping.any?
          @shopping.each { |list| card(list) }
        elsif @finished.empty?
          render Components::EmptyState.new(id: "grocery_lists_empty", icon: "fa-cart-shopping",
                                            message: t(@query.present? ? "grocery_lists.index.empty_search" : "grocery_lists.index.empty"))
        else
          render Components::EmptyState.new(id: "grocery_lists_empty", icon: "fa-cart-shopping", message: t("grocery_lists.index.none_active"))
        end
      end

      finished if @finished.any?
    end
  end

  private

  # Open again on a later page, since that page was asked for from inside it.
  def finished
    div(class: "grocery-lists__completed") do
      render Components::Disclosure.new(key: "grocery-lists-completed", id: "grocery_lists_completed",
                                        title: t("grocery_lists.index.completed", count: @finished.total_entries),
                                        open: @finished.current_page > 1) do
        div(class: "grocery-lists__list") { @finished.each { |list| card(list) } }
        render Components::Pagination.new(collection: @finished, turbo_frame: FRAME_ID, turbo_action: "advance", param_name: FINISHED_PAGE)
      end
    end
  end

  def card(list) = render Views::GroceryLists::Card.new(grocery_list: list, viewer: @viewer)
end
