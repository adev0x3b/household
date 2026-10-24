# frozen_string_literal: true

# A member's shelf as one thing to share: every book they own, now and
# later. Created the first time it is needed (Profile#bookshelf!), shared
# like a recipe (BookshelfShare, how-to-share-models).
class Bookshelf < ApplicationRecord
  include Shareable

  belongs_to :profile

  shared_through :bookshelf_shares

  # The section of the household it belongs to (the share modal's colour).
  def section = :bookshelf

  validates :profile_id, uniqueness: true

  # "Alex's bookshelf": what a share notification calls it.
  def name = I18n.t("bookshelves.name", name: profile.display_name)
end
