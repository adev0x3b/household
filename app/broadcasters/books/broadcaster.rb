# frozen_string_literal: true

module Books
  # Brings the shelf and book pages of everyone who sees a book up to date
  # after it changes, with a Turbo `refresh` over their own signed stream
  # (`turbo_stream_from profile, :books`, opened by Views::Books::Index and
  # Views::Books::Show). A refresh rather than a card: the shelf's grid is
  # sorted, filtered and counted as each reader has it, which only their own
  # page knows, and it is what the writer's own page does after the write.
  # The writer's page skips the refresh its own request caused.
  class Broadcaster < ApplicationBroadcaster
    # `viewers` are read before a deletion, while the book still says who they are.
    def self.changed(book, viewers = book.people_with_access)
      quietly do
        refresh = ApplicationController.helpers.turbo_stream_refresh_tag
        viewers.each { |profile| Turbo::StreamsChannel.broadcast_stream_to(profile, :books, content: refresh) }
      end
    end
  end
end
