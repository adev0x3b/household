# frozen_string_literal: true

require "test_helper"
require "vips"

class MessageTest < ActiveSupport::TestCase
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @direct = Conversation.direct_between(@alice, @bob)
  end

  test "needs words or a picture, from someone in the conversation, within its length" do
    blank = @direct.messages.new(sender: @alice, client_id: SecureRandom.uuid, body: "   ")
    assert_not blank.valid?
    assert blank.errors.of_kind?(:body, :blank)

    stranger = @direct.messages.new(sender: profiles(:carol), client_id: SecureRandom.uuid, body: "hi")
    assert_not stranger.valid?
    assert stranger.errors.of_kind?(:sender, :not_a_participant)

    long = @direct.messages.new(sender: @alice, client_id: SecureRandom.uuid, body: "x" * (Message::BODY_LENGTH + 1))
    assert_not long.valid?
  end

  test "pictures must be pictures, few and small" do
    message = @direct.messages.new(sender: @alice, client_id: SecureRandom.uuid)
    message.images.attach(io: StringIO.new("not an image"), filename: "notes.txt", content_type: "text/plain")
    assert_not message.valid?
    assert message.errors.of_kind?(:images, :not_a_picture)

    message = @direct.messages.new(sender: @alice, client_id: SecureRandom.uuid)
    (Message::MAX_IMAGES + 1).times { |i| message.images.attach(io: File.open(file_fixture("lab_report_sample.png")), filename: "#{i}.png", content_type: "image/png") }
    assert_not message.valid?
    assert message.errors.of_kind?(:images, :too_many)

    message = @direct.messages.new(sender: @alice, client_id: SecureRandom.uuid)
    message.images.attach(io: File.open(file_fixture("lab_report_sample.png")), filename: "scan.png", content_type: "image/png")
    assert_predicate message, :valid?
    assert_equal "📷 Photo", message.preview
  end

  test "a picture is shown shrunk to fit a phone, upright and without its metadata, and a small one as it is" do
    message = send_message(@direct, @alice, "the view")
    message.images.attach(io: StringIO.new(photo(3000, 2000)), filename: "view.jpg", content_type: "image/jpeg")
    message.images.attach(io: StringIO.new(photo(300, 200)), filename: "thumb.jpg", content_type: "image/jpeg")

    large, small = message.images.map { Vips::Image.new_from_buffer(_1.variant(:shown).processed.image.download, "") }

    assert_equal [ 800, 1200 ], [ large.width, large.height ], "at most 1200 on its long side, turned upright"
    assert_equal [ 200, 300 ], [ small.width, small.height ], "never enlarged"
    assert_empty large.get_fields.grep(/exif|xmp|iptc|orientation/), "no metadata left"
  end

  test "unsending empties it in place, reactions and pictures included" do
    message = send_message(@direct, @alice, "oops")
    message.images.attach(io: File.open(file_fixture("lab_report_sample.png")), filename: "scan.png", content_type: "image/png")
    message.message_reactions.create!(profile: @bob, emoji: "😂")

    message.unsend!

    assert_predicate message.reload, :deleted?
    assert_nil message.body
    assert_equal 0, message.message_reactions.count
    assert_equal "Message unsent", message.preview
    assert_not message.message_reactions.new(profile: @bob, emoji: "👍").valid?
  end

  test "a reaction is one emoji, once per person, from someone in the conversation" do
    message = send_message(@direct, @alice, "hi")

    assert_predicate message.message_reactions.create(profile: @bob, emoji: "👍"), :persisted?
    assert_predicate message.message_reactions.create(profile: @bob, emoji: "👍🏽"), :persisted?
    assert_predicate message.message_reactions.create(profile: @alice, emoji: "👍"), :persisted?
    assert_not message.message_reactions.create(profile: @bob, emoji: "👍").persisted?
    %w[a 1 ab 👍👍].each { |bad| assert_not MessageReaction.emoji?(bad), bad }
    assert_not message.message_reactions.create(profile: @bob, emoji: "ab").persisted?
    assert_not message.message_reactions.create(profile: profiles(:carol), emoji: "👍").persisted?

    assert_equal [ [ "👍", [ @bob, @alice ] ], [ "👍🏽", [ @bob ] ] ], message.reload.reactions_by_emoji
  end

  private

  # A camera's JPEG: held sideways (orientation 6 is a quarter turn), with
  # where it was taken and the phone that took it.
  def photo(width, height)
    image = Vips::Image.black(width, height, bands: 3).copy
    image.set_type(GObject::GINT_TYPE, "orientation", 6)
    image.set_type(GObject::GSTR_TYPE, "exif-ifd0-Make", "SpyCam")
    image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitudeRef", "N")
    image.write_to_buffer(".jpg")
  end
end
