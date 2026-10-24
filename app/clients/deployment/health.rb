# frozen_string_literal: true

module Deployment
  # Whether a destination answers, as far as this copy can tell. Staging and
  # dev sit behind Cloudflare Access, which this copy can't pass, so from
  # anywhere else their cards say to open them rather than guess.
  class Health < ApplicationClient
    TIMEOUT = 3 # seconds
    TTL = 30.seconds
    # Nothing sits in front of these, so any copy can ask them.
    PUBLIC = %w[production demo].freeze

    # This copy itself. A worker that can't be checked doesn't count
    # against it: only one seen to be gone does.
    Here = Data.define(:database, :worker) do
      def ok? = database && worker != false
      def key = ok? ? "here_ok" : "here_down"
    end

    # Another destination, through its public health check.
    Public = Data.define(:reachable) do
      def ok? = reachable
      def key = reachable ? "public_ok" : "public_down"
    end

    # A destination this copy can't see: neither up nor down.
    Unknown = Data.define do
      def ok? = nil
      def key = "unknown"
    end

    def self.service = "The health check"

    def self.of(destination)
      destination = destination.to_s
      url = Deployment.url(destination)
      if Deployment.destination == destination
        Here.new(database: Deployment.database_ok?, worker: Deployment.worker_alive?)
      elsif PUBLIC.include?(destination) && url
        Public.new(reachable: Rails.cache.fetch("deployment/health/#{destination}", expires_in: TTL) { reachable?("#{url}/up") })
      else
        Unknown.new
      end
    end

    # A destination that doesn't answer is the very thing this reports, so
    # its error is the answer rather than something to raise.
    def self.reachable?(url)
      perform(Net::HTTP::Head.new(URI(url))).code.to_s == "200"
    rescue Error
      false
    end
  end
end
