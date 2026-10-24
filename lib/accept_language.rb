# frozen_string_literal: true

# A browser's Accept-Language header, read for the first language the app
# speaks, by the header's weights (RFC 9110: "de-DE,de;q=0.9,it;q=0.8" is
# Italian here): "it-IT" counts as "it", and q=0 means "not this one".
class AcceptLanguage
  def initialize(header)
    @header = header.to_s
  end

  # The locale, or nil when the browser asks for nothing the app speaks.
  def locale
    available = I18n.available_locales.map(&:to_s)
    languages.find { available.include?(_1) }&.to_sym
  end

  private

  # The languages asked for, most wanted first; equal weights keep the
  # header's order.
  def languages
    weighted = @header.split(",").filter_map do |range|
      tag, *params = range.split(";").map(&:strip)
      weight = params.find { _1.start_with?("q=") }&.delete_prefix("q=")
      weight = weight ? Float(weight, exception: false).to_f : 1.0
      [ tag.downcase.split("-").first, weight ] if tag.present? && weight.positive?
    end
    weighted.each_with_index.sort_by { |(_, weight), index| [ -weight, index ] }.map { |(language, _), _| language }
  end
end
