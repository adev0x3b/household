# frozen_string_literal: true

require "test_helper"

class LocalesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "picking a language is stored on the profile and used on the next page" do
    patch locale_path, params: { locale: "it" }, headers: { "HTTP_REFERER" => root_url }
    assert_redirected_to root_url
    assert_equal "it", @alice.reload.locale

    get root_path, headers: { "Accept-Language" => "en" }
    assert_select ".account-menu__option.is-current", text: /Italiano/
  end

  test "without a language picked, the browser's first one the app speaks, by its weights" do
    sign_out :profile
    {
      "de-DE,de;q=0.9,it;q=0.8,en;q=0.7" => "it", # the first is past the start of the header
      "en;q=0.4, IT-it" => "it",                  # weights, not order; any case
      "it;q=0, en" => "en",                       # q=0 is "not this one"
      "fr, de" => "en",                           # nothing it speaks: the default
      "" => "en"
    }.each do |header, locale|
      get new_profile_session_path, headers: { "Accept-Language" => header }
      assert_select "html[lang=?]", locale, { count: 1 }, header.inspect
    end
  end

  test "an unknown language is ignored" do
    patch locale_path, params: { locale: "xx" }
    assert_nil @alice.reload.locale
  end

  test "the account menu lists every available language" do
    get root_path
    assert_select ".account-menu__button[aria-expanded=false]"
    assert_equal %i[en it], I18n.available_locales
    assert_select ".account-menu__locale form", count: 2
    assert_select ".account-menu__option.is-current[aria-current=true]", text: /English/
    assert_select ".navbar-assistant-btn", count: 0
  end

  test "the assistant switches to the language picked in the navbar" do
    chat = Assistant::Chat.start!(profile: @alice, locale: :en, time_zone: "Europe/Rome")
    @alice.update!(locale: "it")

    post assistant_chat_messages_path(chat), params: { content: "ciao" }, as: :turbo_stream
    assert_response :accepted
    assert_equal "it", chat.reload.locale
  end

  test "opening a conversation only reads it: its replies stay in the language of its last message" do
    chat = Assistant::Chat.start!(profile: @alice, locale: :en, time_zone: "Europe/Rome")
    @alice.update!(locale: "it", role: :admin)

    get assistant_chat_path(chat, debug: 1)
    assert_equal "en", chat.reload.locale
    assert_select ".assistant-debug__code", text: /Always reply in English/
  end
end
