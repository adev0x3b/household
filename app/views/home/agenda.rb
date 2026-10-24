# frozen_string_literal: true

# Agenda: tasks and the appointments that aren't medical. What's next and
# what's late (as of today), then how we keep up over the selected period,
# each over its report in Reports::Agenda::Dashboard.
class Views::Home::Agenda < Views::Home::Base
  def self.key = :agenda
  ROWS_PER_PAGE = 10

  def self.icon = "fa-calendar-check"

  def self.dashboard(home) = home.agenda

  def self.reports
    [
      Views::Home::Reports::AgendaProgress, Views::Home::Reports::AgendaTiming,
      Views::Home::Reports::AgendaAppointments
    ]
  end

  private

  def content
    tasks = dashboard.tasks

    attention(dashboard.attention)
    kpi_grid(
      completion: { metric: tasks.completion_metric, icon: "fa-circle-check" },
      overdue: { metric: tasks.overdue_metric, icon: "fa-calendar-xmark" },
      attendance: { metric: dashboard.appointments.attendance_metric, icon: "fa-user-check" },
      due_today: { metric: tasks.due_today_metric, icon: "fa-calendar-day", comparison: false },
    )
    task_table(:upcoming, tasks.upcoming_rows, icon: "fa-calendar-week", param: :agenda_upcoming_page)
    task_table(:overdue, tasks.overdue_rows, icon: "fa-calendar-xmark", param: :agenda_overdue_page)
    appointments_table
    report_frames
  end

  def task_table(name, rows, icon:, param:)
    detail_report(name, icon: icon, empty: rows.empty?) do
      paged(rows, param: param, per_page: ROWS_PER_PAGE, list: t("home.agenda.#{name}.title")) do |page|
        render Components::Statistics::DataTable.new(
          caption: t("home.agenda.#{name}.title"), columns: columns(:table, :task, :day, :priority),
        ) do |table|
          page.each do |row|
            table.row do
              table.cell { occurrence_link(row) { row.title } }
              table.cell { day(row.date) }
              table.cell { priority(row.priority) }
            end
          end
        end
      end
    end
  end

  # The next appointments, with their kind and who they're with.
  def appointments_table
    rows = dashboard.appointments.upcoming_rows

    detail_report(:next_appointments, icon: "fa-user-group", empty: rows.empty?) do
      paged(rows, param: :agenda_appointments_page, per_page: ROWS_PER_PAGE, list: t("home.agenda.next_appointments.title")) do |page|
        render Components::Statistics::DataTable.new(
          caption: t("home.agenda.next_appointments.title"),
          columns: columns(:next_appointments, :appointment, :day, :kind, :counterpart),
        ) do |table|
          page.each do |row|
            table.row do
              table.cell { occurrence_link(row) { row.title } }
              table.cell { [ day(row.date), row.occurrence.formatted_start_time ].compact.join(" · ") }
              table.cell { kind(row.kind) }
              table.cell { row.counterpart || format_figure(nil, :count) }
            end
          end
        end
      end
    end
  end

  def priority(value)
    return plain(format_figure(nil, :count)) unless value

    render Views::Tasks::PriorityBadge.new(priority: value)
  end

  def kind(kind) = render(Components::StatusBadge.new(tone: :neutral, icon: Views::Calendar::Cards::AppointmentCard.kind_icon(kind), label: kind.label))
end
