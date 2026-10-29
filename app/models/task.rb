# frozen_string_literal: true

# Something to do on a day (or every week): the Agenda section.
class Task < Event
  has_details "Task::Details"

  validates :title, presence: true

  def self.section = :agenda
  def self.allowed_statuses = %w[pending in_progress completed cancelled skipped]
  def self.named_in_mail? = true

  # Higher sorts earlier on a day card.
  def priority_rank
    Details.priorities.fetch(details.priority.to_s, DEFAULT_PRIORITY_RANK)
  end
end
