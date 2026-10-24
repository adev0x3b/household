# frozen_string_literal: true

module Demo
  # The bookshelf. Alex reads novels, Sam non-fiction, Robin the classics
  # school hands out; each has a pile waiting, reads one book at a time and
  # finishes most of them, with a rating and now and then a note. Alex's
  # whole shelf is shared with Sam; a book or two goes round on its own.
  #
  # Open Library knows every ISBN here; the cover ids were looked up once,
  # by hand, so the seeder never calls the network.
  class Library < Part
    # title, author, ISBN-13, genres, Open Library cover id
    SHELVES = {
      alex: [
        [ "The Left Hand of Darkness", "Ursula K. Le Guin", "9780441478125", [ "Science fiction", "Classics" ], 6989406 ],
        [ "Dune", "Frank Herbert", "9780441013593", [ "Science fiction" ], 14856017 ],
        [ "Circe", "Madeline Miller", "9780316556347", [ "Fantasy", "Mythology" ], 8283869 ],
        [ "Crime and Punishment", "Fyodor Dostoevsky", "9780140449136", [ "Classics", "Russian literature" ], 14935910 ],
        [ "The Handmaid's Tale", "Margaret Atwood", "9780385490818", [ "Dystopia", "Fiction" ], 15162571 ],
        [ "Project Hail Mary", "Andy Weir", "9780593135204", [ "Science fiction" ], 12455001 ],
        [ "The Road", "Cormac McCarthy", "9780307387899", [ "Fiction", "Dystopia" ], 14818100 ],
        [ "Pride and Prejudice", "Jane Austen", "9780141439518", [ "Classics", "Romance" ], 12645114 ],
        [ "The Midnight Library", "Matt Haig", "9780525559474", [ "Fiction", "Fantasy" ], 15164860 ],
        [ "Klara and the Sun", "Kazuo Ishiguro", "9780593318171", [ "Science fiction", "Fiction" ], 10673548 ],
        [ "Everything I Never Told You", "Celeste Ng", "9780143127550", [ "Fiction" ], 12178284 ],
        [ "The Hobbit", "J.R.R. Tolkien", "9780345339683", [ "Fantasy" ], 15214278 ],
        [ "1984", "George Orwell", "9780451524935", [ "Dystopia", "Classics" ], 15257452 ],
        [ "The Lord of the Rings", "J.R.R. Tolkien", "9780544003415", [ "Fantasy", "Classics" ], 13911921 ]
      ],
      sam: [
        [ "Sapiens", "Yuval Noah Harari", "9780062316097", [ "History", "Non-fiction" ], 14369194 ],
        [ "Thinking, Fast and Slow", "Daniel Kahneman", "9780374533557", [ "Psychology", "Non-fiction" ], 7889800 ],
        [ "The Subtle Art of Not Giving a F*ck", "Mark Manson", "9780062457714", [ "Self-help" ], 15262534 ],
        [ "A Brief History of Time", "Stephen Hawking", "9780553380163", [ "Science", "Non-fiction" ], 14589690 ],
        [ "The Power of Habit", "Charles Duhigg", "9780812981605", [ "Psychology", "Self-help" ], 14842390 ],
        [ "Meditations", "Marcus Aurelius", "9780140449334", [ "Philosophy", "Classics" ], 15256763 ],
        [ "The Stranger", "Albert Camus", "9780679720201", [ "Classics", "Philosophy" ], 13151259 ],
        [ "Why We Sleep", "Matthew Walker", "9781501144318", [ "Science", "Non-fiction" ], 15208018 ],
        [ "Guns, Germs, and Steel", "Jared Diamond", "9780393354324", [ "History", "Non-fiction" ], 14631255 ],
        [ "The Body: A Guide for Occupants", "Bill Bryson", "9780385539302", [ "Science", "Non-fiction" ], 9312639 ],
        [ "When Breath Becomes Air", "Paul Kalanithi", "9780812988406", [ "Memoir", "Non-fiction" ], 12390254 ]
      ],
      robin: [
        [ "To Kill a Mockingbird", "Harper Lee", "9780061120084", [ "Classics", "Fiction" ], 15162569 ],
        [ "Lord of the Flies", "William Golding", "9780140283334", [ "Classics", "Fiction" ], 9176044 ],
        [ "Harry Potter and the Philosopher's Stone", "J. K. Rowling", "9780747532699", [ "Fantasy", "Young adult" ], 7355968 ],
        [ "Of Mice and Men", "John Steinbeck", "9780140177398", [ "Classics", "Fiction" ], 15153601 ],
        [ "The Catcher in the Rye", "J. D. Salinger", "9780316769174", [ "Classics", "Coming of age" ], 15171908 ],
        [ "The Great Gatsby", "F. Scott Fitzgerald", "9780743273565", [ "Classics", "Fiction" ], 14314120 ],
        [ "Frankenstein", "Mary Shelley", "9780141439471", [ "Classics", "Gothic" ], 109033 ],
        [ "The Outsiders", "S. E. Hinton", "9780142407332", [ "Young adult", "Coming of age" ], 8743708 ],
        [ "Brave New World", "Aldous Huxley", "9780060850524", [ "Dystopia", "Classics" ], 12992919 ]
      ]
    }.freeze
    # Days a book takes each reader
    PACE = { alex: 9..16, sam: 18..30, robin: 16..28 }.freeze
    # Given up after that many days
    DROPPED = { "Crime and Punishment" => 11, "The Subtle Art of Not Giving a F*ck" => 6 }.freeze
    # A finished book's rating, drawn so that most are liked
    RATINGS = [ 3, 4, 4, 5, 5 ].freeze
    NOTES = {
      "Dune" => "The spice must flow. Sam wants it next.",
      "Circe" => "Read in two sittings on the balcony.",
      "Sapiens" => "Chapter 2 is the one to reread.",
      "The Hobbit" => "Robin's copy from school, with the pencil notes.",
      "Lord of the Flies" => "For the essay due in May."
    }.freeze
    # How many of each pile are on the shelf from the first day; the rest are added as they come up.
    ON_THE_SHELF = 0.6

    def finish
      # Nobody between books today: the next one on the pile is started.
      @readers.each do |reader|
        next if reader.books.reading.exists?

        reader.books.want_to_read.order(:created_at, :id).first&.update!(status: :reading)
      end
    end

    private

    # Its own dice, seeded by the date like the seeder's: the other parts'
    # stories don't change because the shelf draws a few numbers.
    def setup
      @rng = Random.new(start.jd + 13)
      @readers = []
      @books = {}
      SHELVES.each { |who, list| plan_reader(send(who), who, list) }

      at(start + 5) { share(alex.bookshelf!, with: sam) }
      at(start + 40) { share(@books.fetch("Sapiens"), with: alex) }
      at(today - 2) { share(@books.fetch("Circe"), with: robin) }
    end

    def plan_reader(reader, who, list)
      @readers << reader
      shelved = (list.size * ON_THE_SHELF).round
      list.first(shelved).each { |entry| add(reader, entry) }

      # Every book of the pile is on the shelf by today: the later ones a few
      # days before their turn, or today if their turn hasn't come. What is
      # planned after today never happens (at), so the book of the day stays
      # being read and the rest wait.
      day = start + @rng.rand(2..6)
      list.each_with_index do |entry, index|
        title = entry.first
        at(entered(day, @rng.rand(3..10))) { add(reader, entry) } if index >= shelved
        at(day) { @books.fetch(title).update!(status: :reading) }

        if (after = DROPPED[title])
          at(day + after) { @books.fetch(title).update!(status: :dropped, notes: "Not for me, not now.") }
          day += after + @rng.rand(1..4)
        else
          finished = day + @rng.rand(PACE.fetch(who))
          at(finished) { @books.fetch(title).update!(status: :read, rating: RATINGS[@rng.rand(RATINGS.size)], notes: NOTES[title]) }
          day = finished + @rng.rand(1..5)
        end
      end
    end

    def add(reader, (title, author, isbn, genres, cover_id))
      @books[title] ||= Book.create!(profile: reader, title: title, author: author, isbn: isbn, genres: genres, cover_id: cover_id)
    end
  end
end
