# frozen_string_literal: true

# A series shared with a housemate, who can see and change it.
class EventShare < ApplicationRecord
  include Share

  shares :event
end
