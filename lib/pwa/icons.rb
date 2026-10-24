# frozen_string_literal: true

# The installed app's icons, drawn from one geometry (a house on the navbar's
# navy, Theme's) so the SVG and every PNG agree. Swap the shapes or colors
# here and run `bin/rails pwa:icons` again; the files land in public/. Needs
# libvips.
#
# The house sits inside the middle 60% of the canvas, the maskable safe zone,
# so Android can crop the maskable icon to any shape without cutting it.
module Pwa
  module Icons
    BACKGROUND = Theme::SURFACE # the navbar
    HOUSE = Theme::ACCENT

    # On a 512 grid. Roof: apex and eaves; body and door: [x0, y0, x1, y1].
    ROOF = { apex: [ 256, 128 ], left: 120, right: 392, eaves: 252 }.freeze
    BODY = [ 160, 252, 352, 384 ].freeze
    DOOR = [ 232, 304, 280, 384 ].freeze
    CORNER = 112 # the "any" icon's rounded corners; the maskable one is full bleed

    PNGS = {
      "icon-192.png" => [ 192, :rounded ],
      "icon-512.png" => [ 512, :rounded ],
      "icon-maskable-512.png" => [ 512, :full ],
      "apple-touch-icon.png" => [ 180, :full ], # iOS rounds it itself and dislikes transparency
      "badge-96.png" => [ 96, :badge ] # Android's status bar: a white silhouette
    }.freeze

    module_function

    def svg
      apex_x, apex_y = ROOF[:apex]
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
          <rect width="512" height="512" rx="#{CORNER}" fill="#{BACKGROUND}"/>
          <path fill="#{HOUSE}" fill-rule="evenodd" d="M#{apex_x} #{apex_y}L#{ROOF[:right]} #{ROOF[:eaves]}H#{ROOF[:left]}Z#{rect_path(BODY)}#{rect_path(DOOR, reverse: true)}"/>
        </svg>
      SVG
    end

    def rect_path((x0, y0, x1, y1), reverse: false)
      reverse ? "M#{x0} #{y0}V#{y1}H#{x1}V#{y0}Z" : "M#{x0} #{y0}H#{x1}V#{y1}H#{x0}Z"
    end

    # Vips here has no SVG loader, so the shapes are drawn as masks over pixel
    # coordinates (on a 512 grid, scaled down at the end for smooth edges).
    def png(size, style)
      xy = Vips::Image.xyz(512, 512)
      x = xy[0] + 0.5
      y = xy[1] + 0.5

      house = roof_mask(x, y) | rect_mask(x, y, BODY)
      house &= ~rect_mask(x, y, DOOR)

      image =
        if style == :badge
          white = house.ifthenelse(255, 0).cast(:uchar)
          white.bandjoin([ white, white, white ])
        else
          bg = solid(BACKGROUND)
          art = house.ifthenelse(solid(HOUSE), bg)
          alpha = style == :rounded ? rounded_mask(x, y).ifthenelse(255, 0) : ((x * 0) + 255)
          art.bandjoin(alpha.cast(:uchar))
        end

      image.resize(size / 512.0, kernel: :lanczos3).copy(interpretation: :srgb)
    end

    def roof_mask(x, y)
      apex_x, apex_y = ROOF[:apex]
      half = (ROOF[:right] - ROOF[:left]) / 2.0
      spread = half / (ROOF[:eaves] - apex_y)
      (y >= apex_y) & (y <= ROOF[:eaves]) & ((x - apex_x).abs <= (y - apex_y) * spread)
    end

    def rect_mask(x, y, (x0, y0, x1, y1))
      (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)
    end

    # Inside the square with its corners rounded by CORNER.
    def rounded_mask(x, y)
      dx = positive((x - 256).abs - (256 - CORNER))
      dy = positive((y - 256).abs - (256 - CORNER))
      ((dx * dx) + (dy * dy)) <= CORNER * CORNER
    end

    def positive(image) = (image > 0).ifthenelse(image, 0)

    def solid(hex)
      rgb = hex.delete("#").scan(/../).map { _1.to_i(16) }
      Vips::Image.black(512, 512).new_from_image(rgb).cast(:uchar)
    end
  end
end
