# frozen_string_literal: true

# Every admin page, under /admin and the assistant's settings and evals:
# whoever runs the app (Profile#admin?) gets past its door, asked once for
# the whole controller
# (Admin::PlatformPolicy); a page then authorizes what it acts on, as any
# other. The mounted engines' pages (Solid Errors, Mission Control) sit on
# Admin::EnginesController instead: the engines need ActionController::Base.
class Admin::BaseController < ApplicationController
  before_action { authorize :platform, :manage?, policy_class: Admin::PlatformPolicy }

  private

  # The password asked again before the widest of the admin's powers.
  def sudo = (@sudo ||= Admin::Sudo.new(session, current_profile))
end
