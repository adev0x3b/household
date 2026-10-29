# frozen_string_literal: true

require "test_helper"

# Every client of an outside service is an ApplicationClient: one
# deadline, one way to fail — the client's own Error, naming the service.
class ApplicationClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body) do
    def [](_header) = nil
  end

  # A client is a file in a domain's folder (app/clients/books/open_library.rb);
  # what is in a client's own folder are its parts (Delivery::Github's
  # areas of the API, its answers, its canned GitHub).
  test "every client in app/clients is one" do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/clients").to_s)
    files = Dir[Rails.root.join("app/clients/*/*.rb")]
    names = files.map { _1.delete_prefix(Rails.root.join("app/clients/").to_s).delete_suffix(".rb").camelize }

    assert_equal 9, names.size
    names.each do |name|
      assert_operator name.constantize, :<, ApplicationClient, name
      assert_operator name.constantize::Error, :<=, ApplicationClient::Error, name
    end
  end

  test "a service that doesn't answer is the client's Error, naming it, never a socket error" do
    refused = ->(*) { raise Errno::ECONNREFUSED }
    swapping(Net::HTTP, :start, refused) do
      error = assert_raises(Assistant::Connection::Error) { Assistant::Connection.check!(provider: "anthropic", model: "claude-x", api_key: "k") }
      assert_equal "Anthropic isn't answering (ECONNREFUSED)", error.message

      assert_equal :unavailable, Books::OpenLibrary.lookup("9780441013593").reason
    end
  end

  test "an answer outside 2xx, or one that isn't JSON, is the Error too, in the service's words" do
    answer = ->(response) { swapping(Net::HTTP, :start, ->(*) { response }) { Delivery::Github.workflow_runs(limit: 1) } }

    with_env("DEPLOY_DISPATCH_TOKEN" => "tok") do
      assert_raises(Delivery::Github::Error, match: "GitHub answered 503: down for a moment") { answer.(Response.new("503", '{"message":"down for a moment"}')) }
      assert_raises(Delivery::Github::Error, match: "isn't JSON") { answer.(Response.new("200", "<html>")) }
    end
  end
end
