# frozen_string_literal: true

module FontAwesome
  # The icons the browser downloads: Font Awesome Free, kept whole in
  # vendor/fontawesome, cut down to the icons the code names. The stylesheet
  # keeps upstream's own rules and the named icons' rules, and the fonts keep
  # only those icons' glyphs. `bin/rails icons:subset` writes them into
  # vendor/assets/icons/fontawesome, and test/lib/font_awesome_test.rb fails
  # when an icon is added or dropped without running it.
  class Subset
    SOURCE = Rails.root.join("vendor/fontawesome")
    TARGET = Rails.root.join("vendor/assets/icons/fontawesome")
    STYLESHEET = "fontawesome.css"
    FONTS = { solid: "fa-solid-900", regular: "fa-regular-400" }.freeze
    HEADER = "/* Font Awesome Free, cut down to the icons the app names by `bin/rails icons:subset` */"

    # An icon's rule: its name and any aliases, then its glyph as a CSS
    # escape ("\f0f3"). Upstream writes each at the top level, never inside
    # an at-rule.
    ICON_RULE = /(?<selectors>\.fa-[a-z0-9-]+(?:,\.fa-[a-z0-9-]+)*)\{--fa:"(?<glyph>\\\h+ ?)"\}/

    def initialize(names)
      @names = names.to_set
    end

    # Upstream's stylesheet with only the named icons' rules, each under the
    # names the code uses, then each style's own sheet with its font in
    # woff2 alone, which every browser the app supports reads.
    def stylesheet
      icons = source_css("fontawesome").gsub(ICON_RULE) do
        rule = Regexp.last_match
        named = selectors_in(rule[:selectors]) & @names
        named.empty? ? "" : "#{named.sort.map { ".#{_1}" }.join(",")}{--fa:\"#{rule[:glyph]}\"}"
      end
      faces = FONTS.map do |style, font|
        source_css(style).sub(/src:[^;}]+/, %(src:url(#{font}.woff2) format("woff2")))
      end

      [ HEADER, icons, *faces ].join("\n")
    end

    # The named icons' codepoints, in hexadecimal: the glyphs the fonts keep.
    def codepoints
      icon_rules.filter_map { |selectors, glyph| glyph[/\h+/] if selectors_in(selectors).intersect?(@names) }.uniq.sort
    end

    # Names that are neither an icon nor one of upstream's own classes
    # (fa-solid, fa-spin): a typo, or an icon of another version.
    def unknown
      icons = icon_rules.flat_map { |selectors, _| selectors_in(selectors).to_a }
      own = source_css("fontawesome").gsub(ICON_RULE, "").scan(/\.(fa-[a-z0-9-]+)/).flatten
      (@names - icons - own).sort
    end

    # Needs fonttools with brotli (pip install fonttools brotli), whose
    # pyftsubset cuts the fonts.
    def write
      TARGET.join(STYLESHEET).write(stylesheet)
      FONTS.each_value do |font|
        system("pyftsubset", SOURCE.join("webfonts/#{font}.woff2").to_s, "--unicodes=#{codepoints.join(",")}",
               "--flavor=woff2", "--output-file=#{TARGET.join("#{font}.woff2")}", exception: true)
      end
    end

    private

    def icon_rules = source_css("fontawesome").scan(ICON_RULE)

    def selectors_in(group) = group.split(",").map { _1.delete_prefix(".") }.to_set

    def source_css(name) = SOURCE.join("css/#{name}.min.css").read
  end
end
