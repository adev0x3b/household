# frozen_string_literal: true

require "test_helper"

class Book::SeriesTest < ActiveSupport::TestCase
  test "a marked volume is always read, wherever the marker sits" do
    assert_equal({ title: "Jujutsu Kaisen. Sorcery Fight: Dote sprecata", volume: 9 }, Book::Series.parse("Jujutsu Kaisen. Sorcery Fight, Vol. 9: Dote sprecata"))
    assert_equal({ title: "Berserk", volume: 3 }, Book::Series.parse("Berserk, volume 3"))
    assert_equal({ title: "Dragon Ball", volume: 42 }, Book::Series.parse("Dragon Ball n. 42"))
    assert_equal({ title: "Saga", volume: 1 }, Book::Series.parse("Saga #1"))
    assert_equal({ title: "Berserk Max", volume: 16 }, Book::Series.parse("Berserk Max, Band 16"))
    assert_equal({ title: "Fahrenheit", volume: 451 }, Book::Series.parse("Fahrenheit, vol. 451"))
  end

  test "a bare trailing number is a volume when small, or always for comics" do
    assert_equal({ title: "Naruto", volume: 27 }, Book::Series.parse("Naruto 27"))
    assert_equal({ title: "ONE PIECE", volume: 1 }, Book::Series.parse("ONE PIECE 1"))
    assert_equal({ title: "Jujutsu Kaisen – Sorcery Fight: Colonia Tokyo 2 - Grande fortuna -", volume: 21 },
                 Book::Series.parse("Jujutsu Kaisen – Sorcery Fight 21: Colonia Tokyo 2 - Grande fortuna -"))
    assert_equal({ title: "Fahrenheit 451", volume: nil }, Book::Series.parse("Fahrenheit 451"))
    assert_equal({ title: "One Piece", volume: 105 }, Book::Series.parse("One Piece 105", comics: true))
    assert_equal({ title: "1984", volume: nil }, Book::Series.parse("1984"))
    assert_equal({ title: "Catch-22", volume: nil }, Book::Series.parse("Catch-22"))
  end

  test "no number, nothing changes" do
    assert_equal({ title: "Sugar sugar rune. New edition", volume: nil }, Book::Series.parse("Sugar sugar rune. New edition"))
    assert_equal({ title: "", volume: nil }, Book::Series.parse(nil))
  end

  test "comics? reads the genres" do
    assert Book::Series.comics?([ "Comics & Graphic Novels", "Fiction" ])
    assert Book::Series.comics?([ "East Asian Style", "Manga" ])
    assert_not Book::Series.comics?([ "Science fiction", "Classics" ])
  end
end
