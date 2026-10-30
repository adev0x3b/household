# Messages

[Documentation](../README.md) › [Architecture](README.md)

Housemates talk on `/conversations`.

## Conversations

There are two kinds, neither made by a form, and opening Messages makes neither:
- **The household's**, one per household, with every joined member in it (`Conversation.household_conversation`). It is made when the first member joins, and each member who joins later is let in as they join (`Profiles::Join`), history included. Anyone in it can rename it.
- **A direct one** between two housemates, one per pair (`Conversation.direct_between`), keyed by the two ids in order, made by the first press on a housemate's name. It has no name. A stranger to it gets a 404.

A `ConversationParticipant` is a person's place in a conversation, and their **read receipt**: the last message they read, which never moves backwards. Unread counts and "Seen by" are made of it.

## Messages

A `Message` is words, up to `Message::MAX_IMAGES` pictures, or both.
- **Pictures** come from the phone's camera (a `capture="environment"` file input) or its library.
  - **Kept without their metadata:** each is turned upright and saved again, without location or device. What a file is comes from its bytes, not from the type the browser declared, and one that can't be saved again is refused rather than kept as it came (`Messages::CleanPicture`). The sender is told why, nothing of that message is sent, and the admin gets a report.
  - **Two versions:** the page shows a shrunk version, and the original on a tap.
  - **Served by an authorizing controller**, to the conversation's people alone, and cached by their browser only.
- **A send repeated by a bad connection is saved once.** The client mints a UUID for each message, unique per sender.
- **Links** in the words are made clickable, and nothing else is interpreted.
- **Unsending** empties the message in place: its reactions and pictures go, and a placeholder stays.

Every send goes through `Messages::Send`. It saves, broadcasts, and schedules a notification.

**Reactions** are a person's emoji on a message, each emoji once per person (`MessageReaction`, any single pictographic grapheme). A message's smile opens the page's one picker of a few (`Views::Conversations::ReactionPicker`, drawn once rather than on every bubble), and a reaction under a message is a toggle button.

## Live, for every viewer in their own words

`Conversations::Broadcaster` pushes each change to every participant, over a stream signed for that person. A bubble is "mine" or "theirs", and in their language, so it is rendered once per viewer.
- **New message:** the bubble is appended. The sender gets it twice, from the response and from the broadcast, and Turbo settles the two by the bubble's id. The thread is a log, so a screen reader reads a new message as it arrives.
- **Unsent message:** the bubble is replaced.
- **Reaction:** an update of the bubble's reactions alone, so its pictures aren't fetched again.
- **Elsewhere:** the header on a rename, "Seen" on a read, and the conversation's row and the navbar's unread count over the person's notification stream.

The pushes run from a job, not the request, one conversation's at a time and in order (`limits_concurrency` keyed by the conversation).

The open page marks messages read as they arrive while it is visible, keeps the newest message in view, and loads earlier pages by cursor while keeping the reader's place.

## The bell and the phone

A message also tells whoever hasn't read it, after a short delay (`Messages::NotifyJob`). Whoever had the conversation open has read it by then and hears nothing. Everyone else gets one notification per conversation, refreshed by the next message instead of piling up, and pushed to their devices like every notification (Web Push, VAPID).

## Limits

- **Rate limits:** 30 messages and 60 reactions a minute per person.
- **Length:** a message has a length limit.
- **Pictures** can be turned off for an installation (`PICTURES=off`, as on the demo).

Removing a person deletes their messages and reactions, and the direct conversations they were half of. The household's conversation keeps the others' words.

---

Using it: [Messages](../guide/messages.md)
