# frozen_string_literal: true

# The share addresses of a thing, whatever its kind (the routes'
# `shareable` concern): its shares, where a new one is posted, and one
# share on it, where it is taken back.
#
#   paths = Shares::Paths.new(recipe)
#   paths.shares        # => "/recipes/12/shares"
#   paths.share(share)  # => "/recipes/12/shares/3"
class Shares::Paths
  include Rails.application.routes.url_helpers

  # A dom id for the thing among shareables ("recipe-12", "event-7").
  def self.key(thing) = "#{thing.class.base_class.model_name.singular_route_key}-#{thing.id}"

  def initialize(thing)
    @thing = thing
  end

  def shares = polymorphic_path([ *owner, :shares ])

  def share(share) = polymorphic_path([ *owner, :share ], id: share.id)

  private

  # What the thing is addressed as. A series is shared as an Event whatever
  # its kind, since the shares sit under /events. The shelf is the signed-in
  # person's own /bookshelf, which the router names and never numbers, so it
  # can't be handed over as a record.
  def owner
    return [ :bookshelf ] if @thing.is_a?(Bookshelf)

    [ @thing.becomes(@thing.class.base_class) ]
  end
end
