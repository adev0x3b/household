# frozen_string_literal: true

module Assistant
  module Resources
    class Tasks < CalendarResource
      def key = "task"
      def type = Task
      def search_columns = %i[title notes]
      def writable = %w[title notes priority date]
      def enums = { "priority" => Task::Details.priorities.keys }

      def summaries(tasks, _profile)
        tasks.map { |task| { title: task.title, priority: task.details.priority, notes: task.notes.presence&.truncate(120) } }
      end
    end
  end
end
