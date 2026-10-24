# frozen_string_literal: true

# This device's Web Push subscription, from the navbar's "This device" toggle
# (push_controller.js) and from the service worker when the browser replaces
# it (`update`). A subscription is found by its endpoint, never by id: the
# endpoint is what the browser knows.
#
# The browser also keeps which subscription is its own, in a signed cookie
# that lasts like "Remember me" rather than like the session: signing out
# (config/initializers/push_subscriptions.rb) removes it even when the
# browser was closed and reopened since it subscribed.
class PushSubscriptionsController < ApplicationController
  DEVICE_COOKIE = :push_subscription
  # The service worker can't read the page's CSRF token. Another site's
  # PATCH carries no session cookie (SameSite=Lax), but a sibling
  # subdomain's does: same site isn't same origin. What keeps it harmless is
  # that the old endpoint, which only that browser knows, must already be
  # the signed-in profile's.
  skip_forgery_protection only: :update

  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    another_browsers = another_browsers?(subscription)
    subscription.assign_attributes(profile: current_profile, **device_attributes)
    authorize subscription

    if another_browsers
      head :conflict
    elsif subscription.save
      remember_device(subscription)
      head :created
    else
      render json: { errors: subscription.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    if (subscription = current_profile.push_subscriptions.find_by(endpoint: params[:endpoint].to_s))
      authorize subscription
      subscription.destroy!
    else
      skip_authorization # nothing subscribed from this device: nothing to check
    end
    cookies.delete(DEVICE_COOKIE, path: Rails.configuration.x.cookie_path)
    head :no_content
  end

  def update
    subscription = current_profile.push_subscriptions.find_by!(endpoint: params[:old_endpoint].to_s)
    authorize subscription

    PushSubscription.where(endpoint: subscription_params[:endpoint]).where.not(id: subscription.id).delete_all
    subscription.update!(device_attributes.merge(endpoint: subscription_params[:endpoint]))
    remember_device(subscription)
    head :no_content
  end

  private

  # A browser keeps its endpoint when it changes hands, and the next person
  # signed in on it takes the subscription over. But an endpoint can be
  # learnt elsewhere, so someone else's subscription moves only for the
  # browser whose cookie names it. Any other is answered 409, and the switch
  # subscribes its browser afresh, with an endpoint of its own.
  def another_browsers?(subscription)
    return false if subscription.new_record? || subscription.profile_id == current_profile.id

    cookies.signed[DEVICE_COOKIE] != subscription.id
  end

  def remember_device(subscription)
    cookies.permanent.signed[DEVICE_COOKIE] = { value: subscription.id, path: Rails.configuration.x.cookie_path, httponly: true, same_site: :lax }
  end

  # PushSubscription.toJSON(): { endpoint, keys: { p256dh, auth } }
  def subscription_params
    params.expect(subscription: [ :endpoint, keys: %i[p256dh auth] ])
  end

  def device_attributes
    {
      p256dh_key: subscription_params.dig(:keys, :p256dh),
      auth_key: subscription_params.dig(:keys, :auth),
      origin: request.base_url,
      user_agent: request.user_agent.to_s.truncate(255)
    }
  end
end
