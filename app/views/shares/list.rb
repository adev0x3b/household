# frozen_string_literal: true

# Who a thing is shared with, each with a button to stop: in the share
# modal, and on a page that shows it (a file's). The page and the modal over
# it show it at once, so each copy's ids name its place.
class Views::Shares::List < Views::Base
  def self.dom_id(thing, place) = "shares-#{::Shares::Paths.key(thing)}-#{place}"

  # The people a card says it's shared with, in a line.
  def self.names(profiles) = profiles.map(&:display_name).to_sentence

  # place: :page or :modal, whichever this copy is drawn in.
  def initialize(thing:, place:)
    @thing = thing
    @place = place
  end

  # The list itself takes the focus once the last person is taken off it, so
  # it can be read out as no longer shared.
  def view_template
    div(id: dom_id, class: "share-list", tabindex: "-1") do
      if @thing.shares.empty?
        render Components::EmptyState.new(icon: "fa-lock", message: t("shares.not_shared"))
      else
        p(class: "share-list__label") { t("shares.shared_with") }
        shares = @thing.shares.to_a
        names = Profiles::DisplayNames.new(shares.map(&:profile))
        ul(class: "share-list__people") do
          shares.each_with_index { |share, at| person(share, names, around: [ shares[at + 1], (shares[at - 1] if at.positive?) ]) }
        end
      end
    end
  end

  private

  def dom_id = self.class.dom_id(@thing, @place)
  def paths = @paths ||= ::Shares::Paths.new(@thing)

  # around: the next person's share and the one before, where the focus
  # goes once this one is taken off.
  def person(share, names, around:)
    li(class: "share-list__person") do
      span(class: "share-list__name") { names.of(share.profile) }
      render Components::ItemAction.new(id: stop_id(share), href: paths.share(share), icon: "fa-xmark", turbo_stream: true, method: :delete,
                                        label: t("shares.stop", name: share.profile.display_name), danger: true,
                                        data: { focus_fallback: [ *around.compact.map { stop_id(_1) }, dom_id ].join(" ") })
    end
  end

  def stop_id(share) = "#{dom_id}-#{share.id}-stop"
end
