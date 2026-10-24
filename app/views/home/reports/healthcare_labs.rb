# frozen_string_literal: true

# Every analyte measured in the period: latest value, its flag against the
# reference range, and a sparkline of the readings. Out-of-range first.
class Views::Home::Reports::HealthcareLabs < Views::Home::Reports::Base
  def self.page = :healthcare
  def self.report_name = :labs

  private

  def icon = "fa-flask"

  def report = @home.healthcare.labs

  def content
    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.labs.table_caption"),
      columns: columns(:analyte, :latest, :flag, :trend, :readings, numeric: %i[latest readings]),
    ) do |table|
      report.analyte_rows.each do |row|
        table.row do
          table.cell { row.analyte.name }
          table.cell { [ latest_value(row.latest), row.unit&.name ].compact.join(" ") }
          table.cell { flag_badge(row.latest.flag) }
          table.cell { trend(row) }
          table.cell { row.readings.size.to_s }
        end
      end
    end
  end

  # A value is typed in as text; one that is a number reads as the
  # language writes numbers, the rest ("negative", "1:80") as typed.
  def latest_value(reading) = reading.numeric ? format_figure(reading.numeric, :number) : reading.value

  def flag_badge(flag)
    return plain(format_figure(nil, :count)) if flag.nil?

    render Views::LabTestResults::FlagBadge.new(flag: flag)
  end

  def trend(row)
    values = row.trend
    return plain(format_figure(nil, :count)) if values.size < 2

    chart(
      Reports::Chart.new(
        kind: :sparkline, title: t("home.healthcare.labs.trend_title", analyte: row.analyte.name),
        labels: row.readings.select(&:numeric).map { |reading| l(reading.date, format: :short) },
        series: [ Reports::Chart::Series.new(label: row.analyte.name, values: values) ],
      ),
      caption: false,
    )
  end
end
