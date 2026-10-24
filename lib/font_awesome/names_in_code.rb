# frozen_string_literal: true

module FontAwesome
  # Every Font Awesome class the app's code mentions. Views, components,
  # models and scripts name an icon as a whole string ("fa-bell"), never
  # build one from parts, so reading the source finds all of them.
  module NamesInCode
    FILES = %w[app/**/*.{rb,erb,js} lib/**/*.rb].freeze
    # A name followed by a dot is a font's file (fa-solid-900.woff2).
    NAME = /(?<![\w-])fa-[a-z0-9]+(?:-[a-z0-9]+)*(?![\w.-])/

    module_function

    def all
      files.flat_map { File.read(_1).scan(NAME) }.to_set
    end

    # This module's own folder names the fonts' files, which are no icons.
    def files
      own = Rails.root.join("lib/font_awesome").to_s
      FILES.flat_map { Dir[Rails.root.join(_1)] }.reject { _1.start_with?(own) }
    end
  end
end
