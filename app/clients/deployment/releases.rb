# frozen_string_literal: true

module Deployment
  # The newest release GitHub has published for a repository, asked without
  # a token: releases are public, and a self-hosted copy has no token to
  # give. Nil while the repository has published none.
  #
  #   Deployment::Releases.latest("adev0x3b/household")   # => Deployment::Release, or nil
  class Releases < ApplicationClient
    class Error < ApplicationClient::Error; end

    API = "https://api.github.com"
    TAG = /\Av(?<version>\d{4}\.(?:[1-9]|1[0-2])\.[1-9]\d*)\z/

    def self.service = "GitHub's releases"

    def self.latest(repository)
      response = perform(get("#{API}/repos/#{repository}/releases/latest",
                             "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "Household"))
      return if response.code.to_s == "404"

      version = TAG.match(json(response)["tag_name"].to_s)&.[](:version)
      raise Error, "#{service} named a tag that isn't a release's" unless version

      Release.new(repository: repository, version: version)
    end
  end
end
