# frozen_string_literal: true

# A public link is revoked by the file's owner.
class UploadLinkPolicy < ApplicationPolicy
  def destroy? = owner?

  # The links of one's own files: nobody else sees them.
  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(upload_id: Upload.where(profile_id: user.id).select(:id))
  end

  private

  def owning_record = record.upload
end
