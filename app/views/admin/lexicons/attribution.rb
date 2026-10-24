# frozen_string_literal: true

# The data's source and licence, which CC BY-SA asks to be shown.
class Views::Admin::Lexicons::Attribution < Views::Base
  def view_template
    p(class: "lexicons__attribution") do
      plain "#{t("admin.lexicons.attribution")} "
      a(href: "https://kaikki.org/", rel: "noopener", target: "_blank") { "kaikki.org" }
      plain " · "
      a(href: "https://creativecommons.org/licenses/by-sa/4.0/", rel: "noopener", target: "_blank") { "CC BY-SA" }
    end
  end
end
