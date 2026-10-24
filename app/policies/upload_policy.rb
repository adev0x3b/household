# frozen_string_literal: true

# A file is its owner's to rename, share, link, delete and feed chunks to;
# a housemate it is shared with sees it and downloads it. Where the
# installation has uploads off (Platform.uploads?, the demo), nothing new
# comes in and no public link goes out: what is there is seen and downloaded.
class UploadPolicy < ApplicationPolicy
  def index? = true
  def create? = Platform.uploads?
  def show? = owner? || shared?
  def download? = record.ready? && (owner? || shared?)
  def update? = owner?
  def destroy? = owner?
  def link? = owner? && record.ready? && Platform.uploads?
  def chunk? = owner?
  def progress? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end
end
