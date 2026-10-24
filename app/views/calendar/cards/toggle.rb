# frozen_string_literal: true

# The circle on a card: a press on it says the state the day should be in,
# done or not. Inside it, how the day ended: a check, a cross or a skip
# mark, nothing while it is still to do. A viewer who may not change the
# day gets the same circle, inert, saying whose it is in a tooltip and,
# for a screen reader or a phone, which show no tooltip, in words.
#
#   render Views::Calendar::Cards::Toggle.new(occurrence: day, block: "task-card", access: access,
#                                                  label: t("calendar.day_card.complete", title: title))
class Views::Calendar::Cards::Toggle < Views::Base
  include Views::Calendar::DayPaths

  STATUS_ICONS = { "completed" => "fa-check", "cancelled" => "fa-xmark", "skipped" => "fa-forward" }.freeze

  # block: the card's CSS block, whose `__toggle` the circle is; label:
  # what pressing it does; title: the same, shown on hover, where the card
  # wants it.
  def initialize(occurrence:, block:, access:, label:, title: nil)
    @occurrence = occurrence
    @block = block
    @access = access
    @label = label
    @title = title
  end

  def view_template
    if @access.allows?(:change_status?)
      a(id: Views::Calendar::Cards::Base.dom_id(@occurrence, :toggle), href: day_completion_path(@occurrence), class: classes,
        title: @title, aria: { label: @label }, data: { turbo_method: @occurrence.completed? ? :delete : :post, turbo_stream: true }) { status_icon }
    else
      locked = t("links.cards.locked", name: @occurrence.event.profile.display_name)
      span(class: "#{classes} is-locked", title: locked) do
        status_icon
        span(class: "is-sr-only") { locked }
      end
    end
  end

  private

  # A day nothing is saved about yet is drawn, not filled in.
  def classes = "#{@block}__toggle #{@block}__toggle--#{@occurrence.persisted? ? @occurrence.status : "projected"}"

  def status_icon
    icon = STATUS_ICONS[@occurrence.status] if @occurrence.persisted?
    render Components::Icon.new(icon) if icon
  end
end
