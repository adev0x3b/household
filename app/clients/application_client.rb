# frozen_string_literal: true

require "net/http"

# A client of one service outside the app: Open Library, Google
# Books, GitHub, kaikki.org, a model provider, a destination's health check.
# Every client talks to its service the same way:
#
#   get(url, headers)      a request, built here
#   perform(request)       the one call that reaches the network: a deadline to
#                          connect and to read (TIMEOUT, the client's own), and
#                          a service that doesn't answer raises the client's
#                          Error, naming the service — never a socket error
#   json(response)         a 2xx answer as JSON ({} when empty), or the Error
#   text(response)         a 2xx answer's body as UTF-8 text, or the Error
#
# Each client's Error is an ApplicationClient::Error: a caller rescues one
# service's trouble, says what it means to a person, and reports it as a
# warning, since nothing in the app is broken but whoever runs it should
# know the service is down. Tests stub
# `perform`, never Net::HTTP. The helpers serve a client's class methods
# and, for one that carries state (Lexicon::Source, a download), its
# instances alike.
class ApplicationClient
  class Error < StandardError; end

  # What a service that doesn't answer raises from the socket.
  UNREACHABLE = [ SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, EOFError ].freeze
  TIMEOUT = 5 # seconds

  # How the service is named in an error message.
  def self.service = name.demodulize.titleize

  module Requests
    private

    def get(url, headers = {}) = Net::HTTP::Get.new(URI(url), headers)

    # `timeout`: this request's own deadline; `service`: who is asked, when a
    # client talks to more than one; a block reads the answer as it streams
    # (a big download), as Net::HTTP#request does.
    def perform(request, timeout: client::TIMEOUT, service: client.service, &)
      uri = request.uri
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(request, &)
      end
    rescue *UNREACHABLE => e
      raise client::Error, "#{service} isn't answering (#{e.class.name.demodulize})"
    end

    def json(response, service: client.service)
      body = text(response, service: service)
      body.present? ? JSON.parse(body) : {}
    rescue JSON::ParserError
      raise client::Error, "#{service} answered with something that isn't JSON"
    end

    def text(response, service: client.service)
      raise client::Error, "#{service} answered #{response.code}" unless response.code.to_s.start_with?("2")

      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    def client = is_a?(Module) ? self : self.class
  end

  include Requests
  extend Requests
end
