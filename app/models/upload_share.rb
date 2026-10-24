# frozen_string_literal: true

# One file, shared with a housemate: they can see it and download it,
# nothing else. Only a whole file is shared.
class UploadShare < ApplicationRecord
  include Share

  shares :upload

  validate :only_a_ready_file, on: :create

  private

  def only_a_ready_file
    errors.add(:upload, :not_ready) if upload && !upload.ready?
  end
end
