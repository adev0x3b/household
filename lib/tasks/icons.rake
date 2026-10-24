# frozen_string_literal: true

namespace :icons do
  desc "Cut Font Awesome down to the icons the code names (needs pyftsubset: pip install fonttools brotli)"
  task subset: :environment do
    subset = FontAwesome::Subset.new(FontAwesome::NamesInCode.all)
    abort "No Font Awesome icon or class of that name: #{subset.unknown.join(", ")}" if subset.unknown.any?

    subset.write
    puts "#{subset.codepoints.size} icons in #{FontAwesome::Subset::TARGET.relative_path_from(Rails.root)}"
  end
end
