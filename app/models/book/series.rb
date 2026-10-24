# frozen_string_literal: true

# Reads a volume number out of a catalogue title, so a series' volumes
# share one title and differ by number: "Naruto 27" → Naruto, 27;
# "Jujutsu Kaisen. Sorcery Fight, Vol. 9: Dote sprecata" → "Jujutsu Kaisen.
# Sorcery Fight: Dote sprecata", 9; "ONE PIECE 1" → ONE PIECE, 1.
#
# A marker (vol., volume, n., #, tomo, band) is always trusted. A bare
# trailing number is only a volume when it's small (two digits: "Naruto
# 27", never "Fahrenheit 451" or "1984") — or any length when the genres
# say comics or manga, where "One Piece 105" is a volume.
#
#   Book::Series.parse("Naruto 27")                      # => { title: "Naruto", volume: 27 }
#   Book::Series.parse("Fahrenheit 451")                 # => { title: "Fahrenheit 451", volume: nil }
#   Book::Series.parse("One Piece 105", comics: true)    # => { title: "One Piece", volume: 105 }
module Book::Series
  MARKED = /\A(?<before>.+?)[\s,.:;–—-]*(?:\b(?:vol(?:ume)?\.?|n\.|n°|nº|tomo|band|tome)|#)\s*(?<number>\d{1,4})\b(?<after>.*)\z/i
  BARE = /\A(?<before>.+?\S)\s+(?<number>\d{1,3})\z/
  COMICS = /\b(manga|comics?|graphic novels?|fumett[io]|bande dessinée)\b/i

  module_function

  def parse(title, comics: false)
    title = title.to_s.squish
    return { title: title, volume: nil } if title.blank?

    # The number sits on the series' part, before a subtitle ("Sorcery
    # Fight 21: Colonia Tokyo 2"), or on the whole title.
    head, rest = title.split(/:\s+/, 2)
    if rest && (parsed = parse_segment(head, comics))[:volume]
      { title: join(parsed[:title], rest), volume: parsed[:volume] }
    else
      parse_segment(title, comics)
    end
  end

  def parse_segment(segment, comics)
    if (match = segment.match(MARKED))
      { title: join(match[:before], match[:after]), volume: match[:number].to_i }
    elsif (match = segment.match(BARE)) && (comics || match[:number].length <= 2)
      { title: match[:before].sub(/[\s,.:;–—-]+\z/, ""), volume: match[:number].to_i }
    else
      { title: segment, volume: nil }
    end
  end

  # Whether a list of genres says the book is a comic or a manga.
  def comics?(genres) = Array(genres).any? { |genre| genre.to_s.match?(COMICS) }

  # "Sorcery Fight, " + ": Dote sprecata" → "Sorcery Fight: Dote sprecata".
  def join(before, after)
    before = before.sub(/[\s,.:;–—-]+\z/, "")
    after = after.sub(/\A[\s,.:;–—-]+/, "").squish
    after.blank? ? before : "#{before}: #{after}"
  end
end
