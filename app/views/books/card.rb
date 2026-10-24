# frozen_string_literal: true

# One book on the shelf: its cover, what it is, where the reader is with
# it, and its own actions, with the next step (start, finish, read again)
# one tap away.
class Views::Books::Card < Views::Base
  NEXT_ICONS = { "reading" => "fa-play", "read" => "fa-flag-checkered" }.freeze

  def initialize(book:, viewer:)
    @book = book
    @viewer = viewer
  end

  def view_template
    render Components::Card.new(dom_id: "book_#{@book.id}", size: :small) do |card|
      a(href: book_path(@book), class: "book-card__cover-link", aria: { label: @book.display_title }) do
        render Views::Books::Cover.new(book: @book, size: "M")
      end
      card.body { details }
      card.actions { actions }
    end
  end

  private

  def owner? = @book.profile_id == @viewer.id

  def details
    a(href: book_path(@book), class: "book-card__title") { @book.display_title }
    p(class: "book-card__author") { @book.author }
    div(class: "book-card__meta") do
      render Views::Books::StatusBadge.new(status: @book.status)
      render Views::Books::Rating.new(rating: @book.rating, class_name: "book-card__rating") if @book.rating
    end
    render Views::Shares::Whose.new(thing: @book, viewer: @viewer)
    p(class: "book-card__genres") { @book.genres.first(2).join(" · ") } if @book.genres.any?
  end

  # The cover and the title open the book; the buttons are the owner's: the
  # next step one tap away, the rest behind "more".
  def actions
    return unless owner?

    next_status = @book.next_status
    render Components::ItemAction.new(href: book_status_path(@book, status: next_status), icon: next_icon(next_status),
                                      label: t("books.card.next.#{@book.status}"), method: :patch, turbo_stream: true)
    render Components::ItemMenu.new(label: t("books.card.more"), actions: menu_actions)
  end

  def menu_actions
    actions = []
    if @book.reading?
      actions << Components::Action.new(href: book_status_path(@book, status: "dropped"), icon: "fa-ban",
                                        label: t("books.card.drop"), method: :patch, turbo_stream: true)
    end
    actions << Components::Action.new(href: edit_book_path(@book), icon: "fa-pen", label: t("books.card.edit"), turbo_stream: true)
    actions << Components::Action.new(href: new_book_share_path(book_id: @book.id), icon: "fa-share-nodes", label: t("books.card.share"), turbo_stream: true)
    actions << Components::Action.new(href: book_path(@book), icon: "fa-trash", label: t("books.card.destroy"), method: :delete,
                                      confirm: t("books.confirm_destroy", title: @book.title), danger: true)
  end

  # Starting and finishing have their own signs; picking a book up again a turn back.
  def next_icon(next_status) = @book.status.in?(%w[read dropped]) ? "fa-rotate-left" : NEXT_ICONS.fetch(next_status)
end
