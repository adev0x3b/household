# frozen_string_literal: true

# Who may share a thing (Shareable) or stop sharing it: its owner alone,
# and only while it can be shared (a file once it is all there). Asked of
# the thing by SharesController, by the assistant's share operation, and by
# the pages whose top bar offers to share it.
class SharePolicy < ApplicationPolicy
  def share? = owner? && record.shareable?
end
