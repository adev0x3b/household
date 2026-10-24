# frozen_string_literal: true

# The admin's pages (/admin): the app's admin alone, never a
# household's owner. Asked by Admin::BaseController for every action.
class Admin::PlatformPolicy < ApplicationPolicy
  def manage? = user.admin?
end
