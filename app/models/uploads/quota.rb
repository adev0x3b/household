# frozen_string_literal: true

module Uploads
  # A household's room for files, in bytes: the installation's quota
  # (Platform.files_quota), what its members' files
  # take, and what is left. An upload still coming counts whole from the
  # start, since its size was declared: two uploads started together can't
  # both fit in the last gigabyte, which Uploads::Create makes sure of by
  # asking under the household's lock.
  #
  #   quota = Uploads::Quota.new(household)
  #   quota.used        # => 1_016
  #   quota.fits?(75)   # => true
  class Quota
    def initialize(household)
      @household = household
    end

    def total = Platform.files_quota

    def used = @used ||= Upload.where(profile_id: @household.profiles.select(:id)).sum(:byte_size)

    def left = [ total - used, 0 ].max

    def fits?(byte_size) = byte_size <= left
  end
end
