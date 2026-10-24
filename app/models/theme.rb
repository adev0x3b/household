# frozen_string_literal: true

# The app's colours where no stylesheet reaches: the colour the browser paints
# its own bars with (declared by the manifest and by every page), the icons
# drawn into public/, and the error pages served from public/ before the app
# runs. Each constant is one variable of _variables.scss, which stays the
# source; test/models/theme_test.rb fails when the two disagree.
module Theme
  PAGE = "#050a2d"           # $surface-page
  SURFACE = "#151f40"        # $surface-card
  ACCENT = "#fb78ae"         # $accent
  ACCENT_PRESSED = "#f36fb8" # $accent-pressed
  TEXT = "#f0f2f5"           # $text
  MUTED = "#acb1be"          # $text-muted
end
