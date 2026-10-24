# frozen_string_literal: true

# A press on the pipeline. When GitHub refuses one, the admin gets a
# toast rather than the modal again: nothing they could change on the form
# would help.
class Admin::DeliveryRequestsController < Admin::BaseController
  before_action :require_token

  def new
    press = build_press
    return head(:not_found) if press.nil?

    render_modal(modal(press), page: admin_deployment_path)
  rescue Delivery::Github::Error => e
    render turbo_stream: toast(:alert, t("admin.deployment.notices.failed", error: e.message))
  end

  def create
    press = build_press
    return head(:not_found) if press.nil?

    if press.save(by: current_profile)
      render turbo_stream: [ close_modal, toast(:success, pressed_notice(press.request), detail: follow_link(press)),
                             page_refresh ]
    else
      render turbo_stream: redraw_modal(modal(press)), status: :unprocessable_content
    end
  rescue Delivery::Github::Error => e
    render turbo_stream: [ close_modal, toast(:alert, t("admin.deployment.notices.failed", error: e.message)) ]
  end

  private

  # One read of GitHub per request, shared by the modal and the press's checks.
  def pipeline = (@pipeline ||= Delivery::Pipeline.new)

  def build_press
    Delivery::Presses.for(params[:kind])&.new(pipeline: pipeline, sudo: sudo, **given)
  end

  # A card's link names the destination and version at the top level, so a
  # press opens with them; the modal's form then posts them under `press`.
  def given
    params.fetch(:press, {}).permit(:ref, :fresh, :destination, :version, :reason, :typed, :password).to_h.symbolize_keys
      .reverse_merge(params.permit(:destination, :version).to_h.symbolize_keys)
  end

  def modal(press) = Views::Admin::Deliveries::Modals.for(press)

  def pressed_notice(request)
    destination = request.destination && t("admin.deployment.destinations.#{request.destination}")
    t("admin.deployment.notices.pressed.#{request.action}", destination: destination, ref: request.ref, version: request.short_version)
  end

  def follow_link(press)
    helpers.link_to(t("admin.deployment.notices.on_github"), press.workflow_url, target: "_blank", rel: "noopener noreferrer")
  end

  def require_token
    return if Delivery::Github.configured?

    render turbo_stream: toast(:alert, t("admin.deployment.notices.no_token"))
  end
end
