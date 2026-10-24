# frozen_string_literal: true

# A book's status, set in one tap on its card or its page: the press says
# which status it wants.
class BookStatusesController < ApplicationController
  def update
    book = policy_scope(Book).with_everything.find(params[:book_id])
    authorize book, :change_status?

    status = params[:status].to_s.presence_in(Book.statuses.keys) or return refuse(t("refusals.unknown_choice"))
    book.update!(status: status)
    Books::Broadcaster.changed(book)

    redirect_back_after_save(book_path(book), notice: t("books.notices.status.#{status}"))
  end
end
