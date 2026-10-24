# frozen_string_literal: true

# The home dashboard's pages, in the order its tabs show them: the overview
# at "/", then one page per section of the household at /home/<section>.
# HomeController and the tabs read this list, and a page names the
# dashboard it reports on (Views::Home::Base.dashboard), so a new section is
# its page view, a line here, its label at home.tabs.<key> and its row in
# the drawer (Views::Layouts::Navbar::Sheet).
module Views::Home::Pages
  OVERVIEW = Views::Home::Overview

  SECTIONS = {
    "agenda" => Views::Home::Agenda,
    "healthcare" => Views::Home::Healthcare,
    "finance" => Views::Home::Finance,
    "pantry" => Views::Home::Pantry
  }.freeze
end
