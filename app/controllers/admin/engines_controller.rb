# frozen_string_literal: true

# The base of the admin's two borrowed dashboards: Solid Errors
# (/admin/errors) and Mission Control – Jobs (/admin/jobs). Not
# ApplicationController: they are the engines' pages, not ours (no navbar,
# no policy to consult), and only the admin's. The routes let an admin
# in (config/routes.rb); this says so again, so a mount moved outside them
# still answers nobody else.
class Admin::EnginesController < ActionController::Base
  before_action { head :not_found unless current_profile&.admin? }
  # Every language is loaded before an engine's own callbacks run. Mission
  # Control answers in English through an I18n config that knows no other,
  # and translations first loaded under it would leave Italian out of the
  # process until it restarts.
  before_action { I18n.eager_load! }
  around_action :in_admin_zone

  private

  def in_admin_zone(&) = Time.use_zone(current_profile.zone, &)
end
