# frozen_string_literal: true

# The one place a statistic turns into text. Components never
# string-format numbers themselves, so "72%", "€1.234,56" and "12 days"
# read the same everywhere and follow the locale.
module Statistics::Format
  module_function

  def value(value, format)
    return I18n.t("statistics.no_data") if value.nil?

    case format
    when :percent then ActiveSupport::NumberHelper.number_to_percentage(value, precision: 0, locale: I18n.locale)
    when :money then value.to_s
    when :days then I18n.t("statistics.days", count: value.round)
    when :hours then I18n.t("statistics.hours", count: value.round(1), hours: ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1, strip_insignificant_zeros: true, locale: I18n.locale))
    when :number then ActiveSupport::NumberHelper.number_to_rounded(value, precision: 2, strip_insignificant_zeros: true, locale: I18n.locale)
    else ActiveSupport::NumberHelper.number_to_delimited(value.round, locale: I18n.locale)
    end
  end

  # "+4 points", "+3", "+€30,00": the change against the previous period,
  # as a difference. A count or an amount is never put as a percentage:
  # eight late tasks against three read "+167%", which says nothing a
  # reader can picture.
  def delta(metric)
    return nil unless metric.comparable?
    return I18n.t("statistics.delta.no_change") if metric.delta.to_f.zero?

    if metric.format == :percent
      I18n.t("statistics.delta.points", value: signed(metric.delta.round))
    else
      I18n.t("statistics.delta.absolute", value: signed_value(metric.delta, metric.format))
    end
  end

  def signed(number)
    return "0" if number.zero?

    "#{number.positive? ? '+' : '−'}#{ActiveSupport::NumberHelper.number_to_delimited(number.abs, locale: I18n.locale)}"
  end

  def signed_value(delta, format)
    sign = delta.positive? ? "+" : "−"
    "#{sign}#{value(delta.abs, format)}"
  end
end
