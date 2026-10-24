# frozen_string_literal: true

require "test_helper"

# What the installation's limits turn off (Platform, from the environment),
# and that nothing is limited until one is set. The demo installation sets
# them all (config/deploy.demo.yml, DemoBuilders::DEMO_SETTINGS); any
# installation may set some.
class InstallationLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @household = demo_household
    @alex = @household.profiles.find_by!(username: "alex.demo")
    sign_in @alex
  end

  test "invitations off: members invite nobody, the admin still does" do
    on_the_demo do
      get household_path
      assert_select "a[href=?]", new_household_invitation_path(@household), count: 0
      assert_match I18n.t("households.people.invitations_off"), response.body

      assert_no_difference -> { Profile.count } do
        post household_invitations_path(@household), params: { profile: { email: "erin@example.com" } }, as: :turbo_stream
      end
      assert_response :forbidden

      result = Households::Invite.call(@household, inviter: @alex, email: "erin@example.com")
      assert_predicate result, :failure?
      assert result.profile.errors.of_kind?(:base, :invitations_off)

      admin = profiles(:alice).tap { _1.update!(role: :admin) }
      assert_predicate Households::Invite.call(@household, inviter: admin, email: "erin@example.com"), :success?
    end
  end

  test "a day's budget for the assistant, shared by the household" do
    on_the_demo do
      chat = assistant_chat(@alex)
      sam_chat = assistant_chat(@household.profiles.find_by!(username: "sam.demo"))
      29.times { sam_chat.assistant_messages.create!(role: "user", content: "hi") }
      sam_chat.assistant_messages.create!(role: "user", content: "yesterday's", created_at: 1.day.ago)
      sam_chat.assistant_messages.create!(role: "assistant", content: "an answer")

      get assistant_chat_path(chat)
      assert_match "1 of 30 messages left today", response.body
      assert_select ".assistant-composer__btn--attach", count: 0

      assert_enqueued_with(job: Assistant::ReplyJob) do
        post assistant_chat_messages_path(chat), params: { content: "the thirtieth" }, as: :turbo_stream
      end
      assert_response :accepted
      chat.release_reply!

      assert_no_enqueued_jobs do
        post assistant_chat_messages_path(chat), params: { content: "one too many" }, as: :turbo_stream
      end
      assert_response :unprocessable_content
      assert_match "used its 30 assistant messages", response.body
      assert_not chat.reload.replying?
    end
  end

  test "uploads off: nothing new comes in, no public link goes out, what is there is seen and downloaded" do
    file = keep_file(@alex, name: "lease.txt")
    on_the_demo do
      get uploads_path
      assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_upload_path, count: 0
      get new_upload_path, as: :turbo_stream
      assert_response :forbidden
      assert_no_difference -> { Upload.count } do
        post uploads_path, params: { name: "movie.mp4", byte_size: 1000 }, as: :json
      end
      assert_response :forbidden

      get upload_path(file)
      assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_upload_upload_link_path(file), count: 0
      assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_upload_share_path(upload_id: file.id)
      post upload_downloads_path(file)
      assert_redirected_to file_upload_path(file)
      get file_upload_path(file)
      assert_response :success
    end
  end

  test "pictures off: words only, in messages and to the assistant" do
    on_the_demo do
      chat = Conversation.household_conversation(@household)
      get conversation_path(chat)
      assert_select ".conversation-composer input[type=file]", 0

      post conversation_messages_path(chat), params: { body: "hi", images: [ picture_upload ], client_id: SecureRandom.uuid }, as: :turbo_stream
      assert_response :unprocessable_content
      assert_includes response.body, I18n.t("conversations.errors.pictures_off")
      assert_equal 0, chat.messages.count

      assistant = assistant_chat(@alex)
      photo = Rack::Test::UploadedFile.new(StringIO.new("not really"), "image/png", original_filename: "report.png")
      assert_no_enqueued_jobs do
        post assistant_chat_messages_path(assistant), params: { images: [ photo ] }
      end
      assert_response :unprocessable_content
      assert_equal 0, ActiveStorage::Attachment.count
    end
  end

  test "push off: no device subscribes, keys or not, and the line says so" do
    on_the_demo do
      with_push_keys do
        post push_subscription_path, params: { subscription: browser_subscription }, as: :json
        assert_equal 0, PushSubscription.count

        get root_path
        assert_match I18n.t("push.unavailable.not_configured"), response.body
        assert_select "[data-controller~=push]", 0
      end
    end
  end

  test "a day's Open Library lookups, per household" do
    store = ActiveSupport::Cache::MemoryStore.new
    original = Rails.cache
    Rails.cache = store
    dune = Books::Answer.new(attributes: { title: "Dune" }, reason: :found)

    on_the_demo do
      swapping(Books::OpenLibrary, :lookup, ->(_isbn) { dune }) do
        store.write("book_lookups:#{@household.id}:#{Date.current.iso8601}", 49)
        post lookup_books_path, params: { isbn: "9780441013593" }, as: :turbo_stream
        assert_select "input[name='book[title]'][value=Dune]"
        assert_equal 0, Books::LookupAllowance.new(@household).left
        assert_equal 50, Books::LookupAllowance.new(households(:example)).left, "another household counts its own"

        post lookup_books_path, params: { isbn: "9780441013593" }, as: :turbo_stream
        assert_select ".notice", text: /used its lookups for today/
        assert_select "input[name='book[title]'][value=Dune]", count: 0
      end
    end
  ensure
    Rails.cache = original
  end

  test "assistant off: no tab, its pages are a 404, the admin's settings page stays" do
    chat = assistant_chat(@alex)
    with_env("ASSISTANT" => "off") do
      get root_path
      assert_select "a[href=?]", assistant_path, count: 0

      get assistant_path
      assert_response :not_found
      get assistant_chat_path(chat)
      assert_response :not_found
      assert_no_enqueued_jobs do
        post assistant_chat_messages_path(chat), params: { content: "anyone there?" }, as: :turbo_stream
      end
      assert_response :not_found

      sign_in(profiles(:alice).tap { _1.update!(role: :admin) })
      get assistant_settings_path
      assert_response :success
    end

    get root_path
    assert_select "a[href=?]", assistant_path
  end

  test "nothing is limited until the installation says so" do
    chat = assistant_chat(@alex)
    31.times { chat.assistant_messages.create!(role: "user", content: "hi") }

    get assistant_chat_path(chat)
    assert_no_match(/messages left today/, response.body)
    assert_select ".assistant-composer__btn--attach"
    post assistant_chat_messages_path(chat), params: { content: "still fine" }, as: :turbo_stream
    assert_response :accepted

    assert_nil Assistant::MessageAllowance.new(@household).left
    assert_nil Books::LookupAllowance.new(@household).left
    assert_equal Platform.files_quota, Uploads::Quota.new(@household).total
    assert_predicate UploadPolicy.new(@alex, keep_file(@alex)), :link?
    get household_path
    assert_select "a[href=?]", new_household_invitation_path(@household)
    get conversation_path(Conversation.household_conversation(@household))
    assert_select ".conversation-composer input[type=file]"
  end
end
