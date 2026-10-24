# frozen_string_literal: true

# The language a profile picked in the navbar. Null means "none picked yet":
# the browser's Accept-Language decides until they do.
class AddLocaleToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :locale, :string
  end
end
