# frozen_string_literal: true

namespace :pwa do
  desc "Draw the installed app's icons into public/ (SVG + PNGs)"
  task icons: :environment do
    require "vips"

    public_dir = Rails.root.join("public")
    File.write(public_dir.join("icon.svg"), Pwa::Icons.svg)
    puts "public/icon.svg"
    Pwa::Icons::PNGS.each do |name, (size, style)|
      Pwa::Icons.png(size, style).pngsave(public_dir.join(name).to_s, strip: true)
      puts "public/#{name} (#{size}px, #{style})"
    end
  end
end
