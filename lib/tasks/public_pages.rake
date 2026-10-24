# frozen_string_literal: true

namespace :public do
  desc "Write the error pages Rails serves from public/ (400, 404, 406, 422, 500), one per language"
  task pages: :environment do
    Views::PublicPages::Error::PAGES.each_key do |name|
      I18n.available_locales.each do |locale|
        file = Views::PublicPages::Error.file(name, locale)
        File.write(Rails.public_path.join(file), Views::PublicPages::Error.document(name, locale))
        puts "public/#{file}"
      end
    end
  end
end
