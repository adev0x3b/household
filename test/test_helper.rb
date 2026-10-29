# frozen_string_literal: true

# Coverage starts before anything of the app loads, so all of it is
# measured (.simplecov).
require "simplecov"
SimpleCov.start

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "prosopite"
Prosopite.raise = true
Prosopite.rails_logger = false

# Every request a test makes is watched for N+1 queries: a page or an action
# that loads its rows one by one fails the test that asked for it, with no
# list of exceptions. (A whole test isn't watched: its arrange step,
# building records, isn't the app.)
module WatchRequestsForNPlusOne
  def process(...)
    Prosopite.scan { super }
  end
end
ActionDispatch::Integration::Session.prepend(WatchRequestsForNPlusOne)

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    # Under CI each test process loads the whole app and its translations
    # before its first test, as production does, so a file that fails to load
    # or a language loaded by halves fails the run. config.eager_load can't see
    # to it: CI runs the suite as a rake task (test:all), and a rake task boots
    # the app with config.rake_eager_load in its place, which is off. Loading
    # it once before the processes fork would lose coverage: SimpleCov's merge
    # then drops the counts the workers kept of some branches.
    parallelize_setup do |worker|
      TestFileRoots.worker = worker
      Rails.application.config.eager_load_namespaces.each(&:eager_load!) if ENV["CI"].present?
    end

    fixtures :all

    # What every test may build, stand in for, or wait on, without saying
    # so at the top of its file.
    include StatisticsBuilders
    include AssistantBuilders
    include MealBuilders
    include LexiconBuilders
    include DemoBuilders
    include PushBuilders
    include ConversationBuilders
    include NotificationWording
    include LinkBuilders
    include UploadBuilders
    include EveryTable
    include EnvironmentVariables
    include MailBuilders
    include RateLimits
    include Swapping
    include ResponseAssertions
    include Eventually
    include RowLocks
    include QueryCounts
    include LogCapture

    # Rails gives request tests the job helpers; model, service and job
    # tests perform and assert on the jobs they enqueue just as often.
    include ActiveJob::TestHelper

    # Nothing a test leaves behind reaches the next one: the files it wrote,
    # or the language a request switched the process to.
    setup do
      TestFileRoots.reset
      I18n.locale = I18n.default_locale
    end

    # Nothing is sent with the keys .env may hold: push is off until a test
    # turns it on (with_push_keys), no test can start a deploy, Google Books
    # is never asked, and no mail has a relay until a test sets one
    # (with_relay). Every installation limit (Platform) is at its default
    # until a test sets one (with_env, on_the_demo).
    isolate_env "VAPID_PUBLIC_KEY", "VAPID_PRIVATE_KEY", *Platform::ENV_NAMES.values,
                *Platform::LIMITS.values.map(&:env), Platform::OPEN_ACCOUNTS

    # The deployment console sees the same made-up pipeline everywhere, CI
    # included (where Actions sets GITHUB_REPOSITORY): a stand-in repository,
    # the code's and the pipeline's alike, and three addresses under example. No copy is self-hosted until a test
    # hands it a release's image.
    isolate_env "GITHUB_REPOSITORY", "SOURCE_REPOSITORY", "PRODUCTION_HOST", "STAGING_HOST", "DEV_HOST", "HOUSEHOLD_IMAGE"
    setup do
      ENV.update("PRODUCTION_HOST" => "household.example", "STAGING_HOST" => "staging.household.example",
                 "DEV_HOST" => "dev.household.example")
    end
  end
end

module ActionDispatch
  class IntegrationTest
    # Every request test signs someone in; the system tests get the same
    # helpers from their own base class.
    include Devise::Test::IntegrationHelpers
    include TurboRequests
  end
end
