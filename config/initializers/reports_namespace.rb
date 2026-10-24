# frozen_string_literal: true

# app/reports holds the dashboards' reports, all in one namespace:
# app/reports/healthcare/labs.rb is Reports::Healthcare::Labs, not
# Healthcare::Labs. A custom namespace for an autoload root, as Rails'
# autoloading guide describes; the module itself is defined here, outside
# what reloads.
module Reports; end

Rails.autoloaders.main.push_dir(Rails.root.join("app/reports"), namespace: Reports)
