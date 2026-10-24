# frozen_string_literal: true

require "test_helper"

# The log is read by whoever runs the machine and kept wherever logs are
# shipped, so it holds which record a request was about and never what
# anyone wrote: messages, notes, searches and keys stay in the database.
class LogPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "a request logs the ids it names and nothing typed into it" do
    conversation = Conversation.direct_between(@alice, profiles(:bob))
    message = { body: "My results came back positive", client_id: SecureRandom.uuid }

    log = logged { post conversation_messages_path(conversation), params: message, as: :turbo_stream }

    assert_response :created
    assert_match(/"conversation_id"\s*=>\s*"#{conversation.id}"/, log)
    assert_match(/"body"\s*=>\s*"\[FILTERED\]"/, log)
    assert_not_includes log, "positive"
  end

  test "a form's fields are kept out whole, however deeply they are nested" do
    subscription = browser_subscription("https://push.example.com/send/alice-phone")

    log = with_push_keys do
      logged { post push_subscription_path, params: { subscription: subscription }, as: :json }
    end

    assert_response :created
    assert_not_includes log, "alice-phone"
    assert_not_includes log, subscription.dig(:keys, :auth)
  end

  test "the query string of the request line is filtered the same way" do
    log = logged { get books_path(q: "fertility", page: 2) }

    assert_response :success
    assert_includes log, %(Started GET "#{books_path}?page=[FILTERED]&q=[FILTERED]")
    assert_not_includes log, "fertility"
  end

  test "a public file link's token is never logged, nor the address it sends the download to" do
    lease = write_upload_file(uploads(:lease), "lease terms")
    _link, token = mint_link(lease)

    log = logged do
      get public_upload_link_path(token)
      post public_upload_link_path(token)
      follow_redirect!
    end

    assert_response :success
    assert_includes log, %(Started GET "#{Rails.configuration.x.mount_path}/s/[FILTERED]")
    assert_includes log, %(Started POST "#{Rails.configuration.x.mount_path}/s/[FILTERED]")
    assert_includes log, %(Started GET "#{Rails.configuration.x.mount_path}/s/[FILTERED]/file?t=[FILTERED]")
    assert_includes log, "Redirected to [FILTERED]"
    assert_not_includes log, token
  end

  test "an assistant's tool call logs which tool ran and how it went, never what it was asked or found" do
    chat = assistant_chat(@alice)

    log = logged { run_tool(:search_records, chat, type: "therapy", query: "Levothyroxine") }

    assert_match(/\[assistant\] chat=#{chat.id} search_records \d+ms ok$/, log)
    assert_not_includes log, "Levothyroxine"
    debug = logged(level: :debug) { run_tool(:search_records, chat, type: "therapy", query: "Levothyroxine") }
    assert_includes debug, "Levothyroxine", "whoever turns the log to debug sees the call whole"
  end

  test "only an id passes the filter, so a field is private until someone decides otherwise" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    sent = { "id" => "7", "event_id" => "3", "title" => "Oncology", "identity" => "Alice",
             "event" => { "notes" => "Second opinion" } }
    kept = { "id" => "7", "event_id" => "3", "title" => "[FILTERED]", "identity" => "[FILTERED]",
             "event" => "[FILTERED]" }

    assert_equal kept, filter.filter(sent)
  end
end
