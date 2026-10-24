# frozen_string_literal: true

class Components::Base < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TimeAgoInWords

  def t(...) = I18n.t(...)

  # A time is shown on the clock of whoever the page is for: the zone in
  # scope, which is the viewer's for a request and the recipient's inside
  # Profile#as_viewer. Active Record keeps a time in the zone it was first
  # read in, so it is converted here rather than trusted.
  def l(object, **) = I18n.l(object.acts_like?(:time) ? object.in_time_zone : object, **)

  # "3 minutes ago" in the reader's language. A time nobody knows (GitHub
  # left it out) says nothing.
  def time_ago(time)
    return if time.nil?

    t("time.ago", time: time_ago_in_words(time))
  end

  # A figure as the statistics write it: "72%", "12 days", "1.234".
  def format_figure(value, format) = ::Statistics::Format.value(value, format)

  # A select's options: each key worded by the block, and sent as itself.
  #
  #   select_options(Task::Details.priorities.keys) { |key| t("tasks.priority.#{key}") }
  def select_options(keys) = keys.map { |key| [ yield(key), key ] }

  # A number as a field's value: "400" and "0.25", never "400.0", and with
  # a dot in every language, because that is what a number field reads.
  def number_value(value)
    return if value.nil?

    ActiveSupport::NumberHelper.number_to_rounded(
      value, precision: 3, strip_insignificant_zeros: true, separator: ".", delimiter: ""
    )
  end

  # "2.5 kg" or "12 pcs": the number in the reader's language, without
  # trailing zeros.
  def quantity_with_unit(value, unit)
    number = ActiveSupport::NumberHelper.number_to_rounded(
      value, precision: 3, strip_insignificant_zeros: true, locale: I18n.locale
    )
    [ number, unit.respond_to?(:name) ? unit.name : unit ].compact_blank.join(" ")
  end

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
