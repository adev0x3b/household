# frozen_string_literal: true

# The browser's time zone (time_zone_controller.js sends it when it differs
# from the saved one), so a reminder "3 hours before" fires on their clock.
class TimeZonesController < ApplicationController
  without_authorization "the signed-in person's own clock", only: :update

  def update
    zone = params[:time_zone].to_s
    current_profile.update!(time_zone: zone) if ActiveSupport::TimeZone[zone]
    head :no_content
  end
end
