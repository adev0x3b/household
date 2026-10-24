# frozen_string_literal: true

module Assistant
  module Resources
    class Books < Resource
      def key = "book"
      def model = Book
      def search_columns = %i[title author isbn]
      def writable = %w[title volume author isbn genres status started_on finished_on rating notes]
      def enums = { "status" => Book.statuses.keys }

      def scope(profile) = Book.accessible_by(profile)

      def summaries(books, profile)
        books.map do |book|
          { title: book.title, author: book.author, isbn: book.isbn, genres: book.genres.presence, status: book.status,
            started_on: book.started_on&.iso8601, finished_on: book.finished_on&.iso8601, rating: book.rating, notes: book.notes,
            owner: (book.profile.display_name unless book.profile_id == profile.id) }
        end
      end

      private

      def read_for_summaries(books)
        super
        load(books, :profile)
      end
    end
  end
end
