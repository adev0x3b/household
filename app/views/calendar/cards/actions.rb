# frozen_string_literal: true

# A card's own actions, on its right: whose it is when it isn't the
# viewer's, Share for its owner, and, when the viewer may change the day's
# status or delete it, the "more" button that opens the page's menu for it.
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
      more_button if statuses.any? || deletes?
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

  # The menu (Views::Calendar::CardMenu) gives the day another status and
  # deletes it or, for a recurring series, all of it, each part worded as a
  # request when the owner must say yes.
  def more_button
    menu = Views::Calendar::CardMenu
    data = menu.opener_data(repeats: @event.recurring?,
                            delete_url: (day_path(@occurrence) if deletes?), delete_asking: asking_for(:destroy?),
                            status_url: (day_status_path(@occurrence) if statuses.any?), statuses: statuses,
                            status_asking: asking_for(:change_status?))
    render Components::MenuButton.new(label: t("links.cards.more"), controls: menu::ID, data: data)
  end

  def deletes? = @access.allows?(:destroy?)

  # A day still to do can be skipped or cancelled, and one skipped or
  # cancelled can take another of the two or go back to pending. Done and
  # not done is the circle's, so a done day is offered none.
  def statuses
    @statuses ||=
      if !@access.allows?(:change_status?) || @occurrence.completed? then []
      elsif @occurrence.open? then %w[skipped cancelled]
      else %w[skipped cancelled pending] - [ @occurrence.status ]
      end
  end

  def asking_for(query) = (owner_name if @access.asks?(query))
end
