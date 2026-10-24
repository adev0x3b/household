# frozen_string_literal: true

require "test_helper"

# Every kind of shareable goes through the same modal and the same three
# steps; what differs by kind (a calendar to redraw, a file's trail) is
# each kind's hook, tested below the shared steps.
class SharesControllerTest < ActionDispatch::IntegrationTest
  # Each kind: its owner, the thing, and the housemate who has it already.
  KINDS = {
    event: -> { [ profiles(:alice), events(:groceries), profiles(:bob) ] },
    collection: -> { [ profiles(:alice), collections(:b12), profiles(:bob) ] },
    recipe: -> { [ profiles(:alice), recipes(:roast_chicken), profiles(:bob) ] },
    grocery_list: -> { [ profiles(:alice), grocery_lists(:weekly_shop), profiles(:bob) ] },
    book: -> { [ profiles(:bob), books(:hail_mary), profiles(:alice) ] },
    bookshelf: -> { [ profiles(:alice), profiles(:alice).bookshelf!, profiles(:bob) ] },
    upload: -> { [ profiles(:bob), uploads(:photo), profiles(:alice) ] }
  }.freeze

  KINDS.each do |kind, given|
    test "#{kind}: the modal lists who has it, offers the other housemates, and shares from its footer" do
      owner, thing, sharee = arrange(given)
      sign_in owner

      get new_path(kind, thing), as: :turbo_stream

      assert_response :success
      assert_select "turbo-stream[action=update][target=modals] ##{Views::Shares::Modal.dom_id(thing)}" do
        assert_select ".modal__title", text: I18n.t("shares.things.#{kind}.title", name: thing.shared_name)
        assert_select ".modal__body select[name='share[profile_id]']" do
          assert_select "option[value=?]", profiles(:carol).id.to_s
          assert_select "option[value=?]", sharee.id.to_s, count: 0
          assert_select "option[value=?]", profiles(:outsider).id.to_s, count: 0
        end
        assert_select ".modal__body .share-list__person", text: /#{sharee.display_name}/ do
          assert_select "a.item-action[data-turbo-method=delete][href=?]", destroy_path(kind, thing, share_of(thing, sharee))
        end
        assert_select ".modal__footer input[type=submit][value=?]", I18n.t("shares.share")
        assert_select ".modal__footer .modal__btn--cancel", text: I18n.t("modal.done"), message: "a share is done when pressed: nothing to cancel"
      end
    end

    test "#{kind}: sharing tells the person and draws the modal and the page's list again" do
      owner, thing, = arrange(given)
      carol = profiles(:carol)
      sign_in owner

      assert_difference [ -> { thing.shares.count }, -> { carol.notifications.shared.count } ], 1 do
        post create_path(kind, thing), params: { share: { profile_id: carol.id } }, as: :turbo_stream
      end

      assert_response :success
      assert_equal [ owner, thing ], [ carol.notifications.last.actor, carol.notifications.last.subject ]
      assert_redrawn(thing)
      assert_toast I18n.t("shares.notices.shared", name: carol.display_name)
    end

    test "#{kind}: unsharing tells the person and draws both again" do
      owner, thing, sharee = arrange(given)
      sign_in owner

      assert_difference -> { sharee.notifications.unshared.count }, 1 do
        assert_difference -> { thing.shares.count }, -1 do
          delete destroy_path(kind, thing, share_of(thing, sharee)), as: :turbo_stream
        end
      end

      assert_response :success
      assert_redrawn(thing)
      assert_toast I18n.t("shares.notices.unshared", name: sharee.display_name)
    end

    # A shelf in the URL is always the signed-in person's own: nobody else's to try.
    next if kind == :bookshelf

    test "#{kind}: whoever it is shared with can't share it on, or stop it" do
      _owner, thing, sharee = arrange(given)
      share = share_of(thing, sharee)
      sign_in sharee

      assert_no_difference -> { thing.shares.count } do
        post create_path(kind, thing), params: { share: { profile_id: profiles(:carol).id } }, as: :turbo_stream
        delete destroy_path(kind, thing, share), as: :turbo_stream
      end
      assert_response :forbidden
    end
  end

  test "someone outside the household is neither offered nor taken" do
    sign_in profiles(:alice)

    assert_no_difference [ -> { RecipeShare.count }, -> { Notification.count } ] do
      post recipe_shares_path(recipes(:roast_chicken)), params: { share: { profile_id: profiles(:outsider).id } },
                                                        as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_toast I18n.t("shares.errors.pick_someone")
  end

  test "what the person can't see isn't there at all" do
    sign_in profiles(:carol)

    get new_recipe_share_path(recipes(:roast_chicken)), as: :turbo_stream

    assert_response :not_found
  end

  test "the route names the kind: a parameter can't" do
    sign_in profiles(:alice)

    get "#{new_recipe_share_path(recipes(:roast_chicken))}?shareable=Upload", as: :turbo_stream

    assert_select ".modal__title", text: I18n.t("shares.things.recipe.title")
  end

  test "a file still coming isn't shared, not even by its owner" do
    sign_in profiles(:alice)

    get new_upload_share_path(uploads(:backup)), as: :turbo_stream
    assert_response :forbidden

    assert_no_difference [ -> { UploadShare.count }, -> { Notification.count } ] do
      post upload_shares_path(uploads(:backup)), params: { share: { profile_id: profiles(:bob).id } }, as: :turbo_stream
    end
    assert_response :forbidden
  end

  test "when everyone has it, there is no one to pick and nothing to press" do
    sign_in profiles(:alice)
    recipes(:roast_chicken).recipe_shares.create!(profile: profiles(:carol))

    get new_recipe_share_path(recipes(:roast_chicken)), as: :turbo_stream

    assert_select ".modal__body .empty-state", text: I18n.t("shares.no_one_left")
    assert_select ".modal__footer input[type=submit]", count: 0
  end

  # --- What each kind's hook adds --------------------------------------------------

  test "a series shared or unshared is redrawn on that person's calendar" do
    calls = []
    sign_in profiles(:alice)

    swapping(Calendar::DayCardBroadcaster, :call, ->(**options) { calls << options }) do
      post event_shares_path(events(:groceries)), params: { share: { profile_id: profiles(:carol).id } }, as: :turbo_stream
      share = events(:groceries).event_shares.find_by!(profile: profiles(:carol))
      delete event_share_path(events(:groceries), share), as: :turbo_stream
    end

    assert_equal([ [ events(:groceries), [ profiles(:carol) ] ] ] * 2, calls.map { [ _1[:event], _1[:extra_profiles] ] })
  end

  test "a shared collection opens every series in it, and closes them again" do
    carol = profiles(:carol)
    sign_in profiles(:alice)

    post collection_shares_path(collections(:b12)), params: { share: { profile_id: carol.id } }, as: :turbo_stream
    assert Event.accessible_by(carol).exists?(events(:prescription).id)
    assert_equal "Alice shared a therapy with you", wording_of(carol.notifications.last).title, "a healthcare collection is a therapy"

    share = collections(:b12).collection_shares.find_by!(profile: carol)
    delete collection_share_path(collections(:b12), share), as: :turbo_stream
    assert_not Event.accessible_by(carol).exists?(events(:prescription).id)
  end

  test "a shared grocery list refreshes the pages open on it" do
    sign_in profiles(:alice)

    assert_turbo_stream_broadcasts([ grocery_lists(:weekly_shop), profiles(:alice) ], count: 2) do
      post grocery_list_shares_path(grocery_lists(:weekly_shop)), params: { share: { profile_id: profiles(:carol).id } },
                                                                  as: :turbo_stream
    end
  end

  test "a file's shares go on its trail" do
    photo = uploads(:photo)
    sign_in profiles(:bob)

    post upload_shares_path(photo), params: { share: { profile_id: profiles(:carol).id } }, as: :turbo_stream
    delete upload_share_path(photo, upload_shares(:photo_alice)), as: :turbo_stream

    assert_equal([ [ "shared", "Carol" ], [ "unshared", "Alice" ] ], photo.upload_activities.order(:id).last(2).map { [ _1.action, _1.data["with"] ] })
    assert_includes Upload.accessible_by(profiles(:carol)), photo
    assert_not_includes Upload.accessible_by(profiles(:alice)), photo
  end

  test "a shelf shared whole opens every book on it, read-only" do
    alice, carol = profiles(:alice), profiles(:carol)
    sign_in alice

    post bookshelf_shares_path, params: { share: { profile_id: carol.id } }, as: :turbo_stream

    notification = carol.notifications.last
    assert_equal [ "Alice shared their bookshelf with you", "Alice's bookshelf", books_path(shelf: alice.id) ],
                 [ wording_of(notification).title, wording_of(notification).detail, Notifications::Destination.new(notification).path ]
    sign_in carol
    get books_path(shelf: alice.id)
    assert_select "#book_#{books(:dune).id} .share-whose", text: /Alice/
    assert_select "#book_#{books(:dune).id} a.item-action[href*='status']", count: 0
  end

  private

  # The thing as its kind's fixture has it, shared with `sharee` (made when the fixtures don't have it).
  def arrange(given)
    owner, thing, sharee = instance_exec(&given)
    thing.shares.find_or_create_by!(profile: sharee)
    [ owner, thing, sharee ]
  end

  def share_of(thing, profile) = thing.shares.find_by!(profile: profile)

  def new_path(kind, thing) = kind == :bookshelf ? new_bookshelf_share_path : public_send(:"new_#{kind}_share_path", thing)
  def create_path(kind, thing) = kind == :bookshelf ? bookshelf_shares_path : public_send(:"#{kind}_shares_path", thing)
  def destroy_path(kind, thing, share) = kind == :bookshelf ? bookshelf_share_path(share) : public_send(:"#{kind}_share_path", thing, share)

  def assert_redrawn(thing)
    assert_select "turbo-stream[action=replace][target=?]", Views::Shares::Modal.dom_id(thing)
    assert_select "turbo-stream[action=replace][target=?]", Views::Shares::List.dom_id(thing, :page)
  end
end
