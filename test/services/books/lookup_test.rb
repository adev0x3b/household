# frozen_string_literal: true

require "test_helper"

class Books::LookupTest < ActiveSupport::TestCase
  DUNE = "9780441013593"
  ROSE = "9788845292316"
  JUJUTSU = "9788828760887"

  NONE = Books::Answer.new(attributes: {}, reason: :not_found)
  DOWN = Books::Answer.new(attributes: {}, reason: :unavailable)
  GOOGLE = Books::Answer.new(attributes: { title: "Jujutsu Kaisen", author: "G. Akutami", genres: [ "Manga", "Fantasy" ], cover_url: "https://books.google.com/x" },
                             reason: :found)

  # Books::LookupAllowance's two answers, without the cache.
  Spending = Struct.new(:left, keyword_init: true) do
    def any_left? = left.positive?
    def spend! = self.left -= 1
  end

  test "Open Library first; what it has is taken, with its name" do
    result = look_up(DUNE, open_library: found(title: "Dune"))

    assert_predicate result, :success?
    assert_equal [ :open_library, { title: "Dune" } ], [ result.source, result.attributes ]
  end

  test "then Google Books, when a key is configured" do
    result = with_google_key { look_up(ROSE, open_library: NONE, google: found(title: "Il nome della rosa")) }
    assert_equal [ :google_books, "Il nome della rosa" ], [ result.source, result.attributes[:title] ]

    result = look_up(ROSE, open_library: NONE)
    assert_equal [ :not_found, nil ], [ result.error, result.source ]
  end

  test "not found when someone answered and had nothing; unavailable only when nobody could be asked" do
    with_google_key do
      assert_equal :not_found, look_up(ROSE, open_library: NONE, google: NONE).error
      assert_equal :not_found, look_up(ROSE, open_library: DOWN, google: NONE).error
      assert_equal :unavailable, look_up(ROSE, open_library: DOWN, google: DOWN).error
    end
  end

  test "spent lookups stop it before anyone is asked, and every lookup made spends one" do
    allowance = Spending.new(left: 1)

    result = look_up(DUNE, open_library: NONE, allowance: allowance)
    assert_equal [ :not_found, 0 ], [ result.error, allowance.left ], "a lookup that found nothing still asked"

    result = look_up(DUNE, allowance: allowance)
    assert_equal [ :capped, 0 ], [ result.error, allowance.left ]
  end

  test "an Open Library hit without a cover or genres takes Google's, and nothing else of Google's" do
    bare = found(title: "Jujutsu Kaisen. Sorcery Fight", author: "Gege Akutami")
    result = with_google_key { look_up(JUJUTSU, open_library: bare, google: GOOGLE) }

    assert_equal :open_library, result.source
    assert_equal({ title: "Jujutsu Kaisen. Sorcery Fight", author: "Gege Akutami", cover_url: "https://books.google.com/x", genres: [ "Manga", "Fantasy" ] },
                 result.attributes)
  end

  test "Google tops up only what is missing: a cover alone, genres alone" do
    with_google_key do
      result = look_up(JUJUTSU, open_library: found(title: "T", author: "A", genre_list: "Manga"), google: GOOGLE)
      assert_equal({ title: "T", author: "A", genre_list: "Manga", cover_url: "https://books.google.com/x" }, result.attributes)

      result = look_up(JUJUTSU, open_library: found(title: "T", author: "A", cover_id: 7), google: GOOGLE)
      assert_equal({ title: "T", author: "A", cover_id: 7, genres: [ "Manga", "Fantasy" ] }, result.attributes)
    end
  end

  test "a complete hit, no key, or Google having nothing leaves Open Library's record alone" do
    complete = found(title: "Dune", author: "Frank Herbert", genre_list: "Science fiction", cover_id: 1)
    bare = found(title: "Jujutsu Kaisen. Sorcery Fight", author: "Gege Akutami")

    with_google_key do
      assert_equal complete.attributes, look_up(DUNE, open_library: complete).attributes
      assert_equal bare.attributes, look_up(JUJUTSU, open_library: bare, google: NONE).attributes
    end
    assert_equal bare.attributes, look_up(JUJUTSU, open_library: bare).attributes
  end

  test "a numbered title becomes the series' title and its volume; an unnumbered one stays" do
    naruto = found(title: "Naruto 27", author: "Masashi Kishimoto", genre_list: "Manga", cover_id: 1)
    assert_equal [ "Naruto", 27 ], look_up("9788828767640", open_library: naruto).attributes.values_at(:title, :volume)

    one_piece = found(title: "One Piece 105", author: "Eiichiro Oda", genres: [ "Comics & Graphic Novels", "Manga" ], cover_url: "x")
    assert_equal [ "One Piece", 105 ], look_up("9788822605115", open_library: one_piece).attributes.values_at(:title, :volume)

    novel = found(title: "Fahrenheit 451", author: "Ray Bradbury", genre_list: "Dystopia", cover_id: 1)
    assert_equal [ "Fahrenheit 451", nil ], look_up("9781451673319", open_library: novel).attributes.values_at(:title, :volume)
  end

  private

  # Books::Lookup with each catalogue answering as given. A catalogue given
  # no answer must not be asked at all.
  def look_up(isbn, open_library: nil, google: nil, **options)
    swapping(Books::OpenLibrary, :lookup, answering(open_library, "Open Library")) do
      swapping(Books::GoogleBooks, :lookup, answering(google, "Google Books")) { Books::Lookup.call(isbn, **options) }
    end
  end

  def answering(answer, name) = answer ? ->(_isbn) { answer } : ->(_isbn) { flunk "#{name} isn't asked" }

  def found(**attributes) = Books::Answer.new(attributes: attributes, reason: :found)

  def with_google_key(&) = with_env("GOOGLE_BOOKS_API_KEY" => "test-key", &)
end
