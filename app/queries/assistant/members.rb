# frozen_string_literal: true

module Assistant
  # The other people in the household (the profile's housemates, as the share
  # and "paid by" forms offer them), and who "Marco" or "marco.r" means.
  #
  #   Members.new(profile).resolve("Marco")
  #   # => Resolution(profile: #<Profile Marco>, candidates: [], problem: nil)
  class Members
    Resolution = Data.define(:profile, :candidates, :problem)

    def initialize(profile)
      @profile = profile
    end

    def all = @profile.housemates.by_name

    def names = all.map { |p| label(p) }

    def label(person) = person.display_name

    # An exact first name, username or full name first, ignoring accents;
    # then every word said appearing in one person's name; then a misspelled
    # name ("Marko"). Several are candidates, and none is a problem naming
    # who there is.
    def resolve(words)
      said = TextMatch.fold(words.to_s.squish)
      return Resolution.new(profile: nil, candidates: [], problem: "say who") if said.empty?

      people = all.to_a
      found = people.select { |p| aliases(p).any? { |n| TextMatch.fold(n) == said } }.presence ||
              people.select { |p| said.scan(/[[:alnum:]]+/).all? { |w| TextMatch.fold(full_name(p)).include?(w) } }.presence ||
              people.select { |p| aliases(p).any? { |n| TextMatch.typo?(said, n) } }
      case found.size
      when 1 then Resolution.new(profile: found.first, candidates: [], problem: nil)
      when 0 then Resolution.new(profile: nil, candidates: [], problem: "nobody called #{words} in the household (there is: #{names.to_sentence})")
      else Resolution.new(profile: nil, candidates: found.map { |p| { id: p.id, name: full_name(p) } }, problem: nil)
      end
    end

    private

    def aliases(person) = [ person.first_name, person.username, full_name(person) ].compact_blank

    def full_name(person) = [ person.first_name, person.last_name, person.username ].compact_blank.join(" ")
  end
end
