# frozen_string_literal: true

# A card's own actions, on its right: whose it is when it isn't the
# viewer's, Share for its owner, and, when the viewer may delete the day,
# the "more" button that opens the page's menu of deletes for it.
class Views::Calendar::Cards::Actions < Views::Base
  include Views::Calendar::DayPaths

  def initialize(occurrence:, access:)
    @occurrence = occurrence
    @event = occurrence.event
    @access = access
  end

  def view_template
    div(class: "card-actions") do
      owner_tag unless @access.owner?
      share_button if @access.owner?
      more_button if @access.allows?(:destroy?)
    end
  end

  private

  def owner_name = @event.profile.display_name

  def owner_tag
    span(class: "card-actions__owner section--links", title: t("links.cards.owner", name: owner_name)) { owner_name }
  end

  def share_button
    render Components::ItemAction.new(href: new_event_share_path(event_id: @event.id), icon: "fa-share-nodes",
                                      label: t("calendar.day_card.share", title: @occurrence.event_label), turbo_stream: true)
  end

  # The menu (Views::Calendar::CardMenu) deletes this day or, for a
  # recurring series, all of it, worded as a request when the owner must
  # say yes.
  def more_button
    menu = Views::Calendar::CardMenu
    asking = owner_name if @access.asks?(:destroy?)
    render Components::MenuButton.new(label: t("links.cards.more"), controls: menu::ID,
                                      data: menu.opener_data(url: day_path(@occurrence), repeats: @event.recurring?, asking: asking))
  end
end
