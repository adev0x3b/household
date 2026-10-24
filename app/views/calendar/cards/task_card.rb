# frozen_string_literal: true

# A task's day: its title, its priority when it is pressing, and its status.
class Views::Calendar::Cards::TaskCard < Views::Calendar::Cards::Base
  def self.icon = "fa-clipboard-list"

  private

  def prefix = "task-card"

  def content
    div(class: "task-card__content") do
      div(class: "task-card__header") do
        title_link
        priority_badge
      end

      outcome
      attached_costs
    end
  end

  def priority_badge
    priority = details.priority
    return unless Views::Tasks::PriorityBadge.pressing?(priority)

    render Views::Tasks::PriorityBadge.new(priority: priority)
  end
end
