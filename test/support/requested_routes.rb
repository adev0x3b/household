# frozen_string_literal: true

# Every action a route reaches is requested by some test: an action nobody
# asks for is one nobody knows still works. Each request test notes the
# actions it reached (in its result's metadata, so a parallel worker's
# reach the parent); once the whole suite has run, the run fails listing
# the routes no test requested. Checked where the whole suite runs — CI, and
# bin/ci, which sets CI too — like the coverage floor (.simplecov).
module RequestedRoutes
  mattr_accessor :reached, default: Set.new

  # The actions config/routes.rb draws, "controller#action" (no gem draws
  # any: config/application.rb turns theirs off). A mounted engine and a
  # redirect name no action.
  def self.drawn
    Rails.application.routes.routes.filter_map do |route|
      controller, action = route.defaults.values_at(:controller, :action)
      "#{controller}##{action}" if controller && action
    end.uniq.sort
  end

  module Recording
    def process(...)
      super.tap do
        controller, action = request.path_parameters.values_at(:controller, :action)
        RequestedRoutes.reached << "#{controller}##{action}" if controller && action
      end
    end
  end

  module PerTest
    extend ActiveSupport::Concern

    included do
      setup { RequestedRoutes.reached = Set.new }
      teardown { metadata[:requested_routes] = RequestedRoutes.reached.to_a }
    end
  end

  # In the process that reports: gathers every test's actions and, at the
  # end, fails the run if a drawn one was never reached.
  class Reporter < Minitest::AbstractReporter
    def initialize(io)
      @io = io
      @reached = Set.new
    end

    def record(result)
      @reached.merge(result.metadata.fetch(:requested_routes, [])) if result.metadata?
    end

    def report
      return if passed?

      @io.puts "\nNo test requests #{unrequested.size} of the actions config/routes.rb draws:"
      unrequested.each { @io.puts "  #{_1}" }
    end

    def passed?
      unrequested.empty?
    end

    private

    def unrequested
      RequestedRoutes.drawn - @reached.to_a
    end
  end

  def self.minitest_plugin_init(options)
    Minitest.reporter << Reporter.new(options[:io]) unless ENV["CI"].to_s.empty?
  end
end

ActionDispatch::Integration::Session.prepend(RequestedRoutes::Recording)
ActionDispatch::IntegrationTest.include(RequestedRoutes::PerTest)
Minitest.register_plugin(RequestedRoutes)
