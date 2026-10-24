# frozen_string_literal: true

# GitHub, as the delivery console reads and drives it. It needs the deploy
# token, whose permissions the deployment runbook lists; without one the console
# shows this copy's facts and no buttons. It asks two repositories, which
# are one unless the pipeline runs from a private repository of its own:
# the code's (Deployment.source_repository) for commits, pull requests and
# CI, and the pipeline's (Deployment.repository) for the Deploy workflow,
# the freeze and the Deployments.
module Delivery
  class Github < ApplicationClient
    class Error < ApplicationClient::Error; end

    API = "https://api.github.com"
    WORKFLOW = "deploy.yml"
    CI_WORKFLOW = "ci.yml"
    ACTIONS = %w[deploy restart rollback release preview stop].freeze
    # A run that hasn't ended: the page keeps polling while one is listed.
    LIVE = %w[queued in_progress waiting pending requested].freeze
    # A deployment status that may still change.
    LIVE_STATES = %w[queued pending in_progress].freeze
    # How long an answer is kept: one that moves, one a commit pins down.
    LIVE_TTL = 10.seconds
    STILL_TTL = 1.day
    FREEZE = "DEPLOY_FREEZE"
    FREEZE_NOTE = "DEPLOY_FREEZE_NOTE"
    EXPIRY_HEADER = "github-authentication-token-expiration"
    EXPIRY_KEY = "delivery/github/token_expires_at"
    SHA = /\A\h{40}\z/

    # What it asks, by area of GitHub's API (github/workflows.rb, …); the
    # answers are values that read GitHub's JSON themselves (github/run.rb, …).
    extend Workflows
    extend Repository
    extend Deployments
    extend Variables

    class << self
      def service = "GitHub"

      def token = Canned.on? ? "canned" : Platform.deploy_dispatch_token
      # A self-hosted copy has no pipeline of its own to read, whatever token it may hold.
      def configured? = Deployment.pipeline? && token.present?

      # What the token can read, for the settings page: { actions: true | "GitHub answered 403: …", … }.
      # Writes aren't tried: they would start something.
      def check
        {
          actions: try { call(get("/actions/workflows/#{WORKFLOW}/runs", per_page: 1)) },
          contents: try { call(get("/commits/main", repository: source)) },
          deployments: try { call(get("/deployments", per_page: 1)) },
          pull_requests: try { call(get("/pulls", per_page: 1, repository: source)) },
          variables: try { call(get("/actions/variables", per_page: 1)) }
        }
      end

      # The repository a workflow is in: CI's is the code's, Deploy's the pipeline's.
      def repository_of(workflow) = workflow == CI_WORKFLOW ? source : Deployment.repository

      # When the token expires, as GitHub last said; nil when it never said.
      def token_expires_at = Rails.cache.read(EXPIRY_KEY)

      private

      def headers
        { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "Household", "Content-Type" => "application/json" }
      end

      def source = Deployment.source_repository

      # Every request is about one of the two repositories, so callers name
      # a path inside it (`get("/branches", repository: source)`) rather
      # than a URL: the pipeline's, unless they name the code's.
      def uri(path, query, repository)
        query = query.compact
        URI("#{API}/repos/#{repository}#{path}#{"?#{query.to_query}" if query.any?}")
      end

      def get(path, repository: Deployment.repository, **query) = Net::HTTP::Get.new(uri(path, query, repository), headers)
      def delete(path) = Net::HTTP::Delete.new(uri(path, {}, Deployment.repository), headers)

      def post(path, repository: Deployment.repository, **body)
        Net::HTTP::Post.new(uri(path, {}, repository), headers).tap { _1.body = body.to_json }
      end

      def patch(path, body)
        Net::HTTP::Patch.new(uri(path, {}, Deployment.repository), headers).tap { _1.body = body.to_json }
      end

      def put(path, repository: Deployment.repository, **body)
        Net::HTTP::Put.new(uri(path, {}, repository), headers).tap { _1.body = body.to_json }
      end

      # Sends and reads: a Hash or Array, or the Error GitHub gave.
      def call(request) = json(perform(request))

      def try
        yield
        true
      rescue Error => e
        e.message
      end

      # A 2xx answer's body as it came, else the Error with GitHub's own message.
      def text(response, service: self.service)
        return super if response.code.to_s.start_with?("2")

        message = message_in(response.body.to_s)
        raise Error, "#{service} answered #{response.code}#{": #{message}" if message}"
      end

      # A proxy in front of GitHub can answer an error with an HTML page, which
      # has no message to quote.
      def message_in(body)
        JSON.parse(body)["message"].presence
      rescue JSON::ParserError, TypeError, NoMethodError
        nil
      end

      # A read kept in the cache: `ttl` is a duration, or a lambda given the
      # value (a status that can still change is kept for seconds, one that
      # ended for a day). An Error isn't kept.
      def cached(key, ttl)
        key = cache_key(key)
        found = Rails.cache.read(key)
        return found unless found.nil?

        value = yield
        Rails.cache.write(key, value, expires_in: ttl.respond_to?(:call) ? ttl.call(value) : ttl)
        value
      end

      # Drops what a write made stale (the runs' lists are kept seconds anyway).
      def forget(key) = Rails.cache.delete(cache_key(key))

      def cache_key(key) = "delivery/github/#{key}"

      # The network (ApplicationClient#perform), with the token checked first,
      # the canned answers where they stand in for GitHub, and the token's
      # expiry, which rides on every answer's headers.
      def perform(request, **)
        raise Error, "no deploy token is set" unless configured?
        return Canned.perform(request) if Canned.on?

        super.tap { remember_expiry(_1) }
      end

      def remember_expiry(response)
        expiry = response[EXPIRY_HEADER].presence
        return if expiry.nil?

        Rails.cache.write(EXPIRY_KEY, Time.zone.parse(expiry), expires_in: 1.week)
      rescue ArgumentError => e
        Rails.error.report(e, handled: true, context: { header: EXPIRY_HEADER, value: expiry })
      end
    end
  end
end
