# frozen_string_literal: true

# A collection shared with a housemate, who can change it and sees every
# series in it, now and later (Event.accessible_by's collection branch).
class CollectionShare < ApplicationRecord
  include Share

  shares :collection
end
