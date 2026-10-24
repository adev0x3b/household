# frozen_string_literal: true

# The pipeline's two frames on /admin/deployment. They load after the page,
# so a slow GitHub never holds up what this copy can say about itself.
class Admin::DeliveriesController < Admin::BaseController
  def console
    pipeline = Delivery::Pipeline.new
    render Views::Admin::Deliveries::Console.new(pipeline: pipeline, requests: Delivery::Request.recent_first.limit(Delivery::Pipeline::RUNS).to_a,
                                                 token_expiry: Delivery::TokenExpiry.current,
                                                 active: pipeline.live? || Delivery::Request.watching.exists?), layout: false
  rescue Delivery::Github::Error => e
    render Views::Admin::Deliveries::Console.new(error: e.message), layout: false
  end

  def metrics
    render Views::Admin::Deliveries::Metrics.new(metrics: Delivery::Metrics.for_production.all), layout: false
  rescue Delivery::Github::Error => e
    render Views::Admin::Deliveries::Metrics.new(error: e.message), layout: false
  end
end
