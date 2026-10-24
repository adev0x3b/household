# frozen_string_literal: true

# A collection in the list: its name and whether it is running, paused or
# done, whose it is, and what the viewer may do with it. A housemate it is
# shared with may edit it; only its owner shares or deletes it.
class Views::Collections::Card < Views::Base
  def initialize(collection:, viewer:)
    @collection = collection
    @viewer = viewer
  end

  def view_template
    render Components::Card.new(dom_id: "collection_#{@collection.id}") do |card|
      card.header { header_content }
      card.body { render Views::Shares::Whose.new(thing: @collection, viewer: @viewer) }
      card.actions { actions }
    end
  end

  private

  def owner?
    @collection.profile_id == @viewer.id
  end

  def shared?
    @collection.shared_profiles.include?(@viewer)
  end

  def header_content
    a(href: collection_path(@collection), class: "collection-card__name") { @collection.name }
    render Views::Collections::StatusBadge.new(status: @collection.status)
  end

  # The name opens the collection; editing is on the card, sharing and
  # deleting, the owner's, behind "more".
  def actions
    if owner? || shared?
      render Components::ItemAction.new(href: edit_collection_path(@collection), icon: "fa-pen", label: t("collections.card.edit"), turbo_stream: true)
    end
    render Components::ItemMenu.new(label: t("collections.card.more"), actions: menu_actions)
  end

  def menu_actions
    return [] unless owner?

    [
      Components::Action.new(href: new_collection_share_path(collection_id: @collection.id), icon: "fa-share-nodes",
                             label: t("collections.card.share"), turbo_stream: true),
      Components::Action.new(href: collection_path(@collection), icon: "fa-trash", label: t("collections.card.destroy"),
                             method: :delete, confirm: t("collections.confirm_destroy", name: @collection.name), danger: true)
    ]
  end
end
