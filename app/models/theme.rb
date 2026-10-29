# frozen_string_literal: true

# The app's colours where no stylesheet reaches: the colour the browser paints
# its own bars with (declared by the manifest and by every page), the icons
# drawn into public/, the error pages served from public/ before the app
# runs, and the mail (Views::Emails::Message). Each constant is one variable
# of _variables.scss, which stays the source; test/models/theme_test.rb
# fails when the two disagree.
module Theme
  PAGE = "#050a2d"           # $surface-page
  SURFACE = "#151f40"        # $surface-card
  ACCENT = "#fb78ae"         # $accent
  ACCENT_PRESSED = "#f36fb8" # $accent-pressed
  TEXT = "#f0f2f5"           # $text
  MUTED = "#acb1be"          # $text-muted
  MAIL_PAGE = "#f3f4f7"      # $mail-page
  MAIL_CARD = "#fff"         # $mail-card
  MAIL_TEXT = "#1d2233"      # $mail-text
  MAIL_MUTED = "#5d6375"     # $mail-muted
end
