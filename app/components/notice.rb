# frozen_string_literal: true

# A few lines that ask for the reader's attention, above a page's report or
# a form's fields. Its tone says how much: :neutral for news, :action when
# the reader must do something, :critical for what went wrong, which is
# announced as an alert.
#
#   render Components::Notice.new(tone: :action) { p { t("…") } }
class Components::Notice < Components::Base
  TONES = %i[neutral action critical].freeze

  def initialize(tone: :neutral)
    raise ArgumentError, "unknown notice tone: #{tone.inspect}" unless TONES.include?(tone)

    @tone = tone
  end

  def view_template(&)
    div(class: "notice notice--#{@tone}", role: ("alert" if @tone == :critical), &)
  end
end
