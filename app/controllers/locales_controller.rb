# frozen_string_literal: true

# The navbar's language switch. The choice is stored on the profile, so it
# sticks across devices; the assistant replies in it too.
class LocalesController < ApplicationController
  without_authorization "the signed-in person's own language", only: :update

  def update
    locale = params[:locale].to_s
    current_profile.update!(locale: locale) if I18n.available_locales.map(&:to_s).include?(locale)
    redirect_back_or_to root_path, status: :see_other
  end
end
