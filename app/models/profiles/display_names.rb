# frozen_string_literal: true

# What to call each of several people shown together (a picker, a table of
# who owes whom): their display name, with their username after it only
# when another of them has the same display name, so two people called
# Alex are told apart and everyone else is simply their name.
class Profiles::DisplayNames
  def initialize(profiles)
    @profiles = profiles.to_a
  end

  def of(profile)
    name = profile.display_name
    return name if name == profile.username || @profiles.none? { |other| other != profile && other.display_name == name }

    I18n.t("profiles.identifying_name", name: name, username: profile.username)
  end
end
