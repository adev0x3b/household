# Sharing and links

[Documentation](../README.md) › [Architecture](README.md)

Housemates can let each other in on their things in two ways:
- **Sharing**: one thing (a recipe, a grocery list, a file, a series on the calendar, a whole bookshelf) is shared with one housemate.
- **Linking**: two housemates link their calendars, and each says what the other may do with their days, kind by kind.

## Sharing a thing

Every shareable kind works the same way:

- **A share is a row in its kind's own table**: `RecipeShare`, `GroceryListShare`, `UploadShare`, `EventShare`, `CollectionShare`, `BookShare`, `BookshelfShare`. Each has a real foreign key on both sides.
  - The tables all `include Share`, so they hold the same rules: unique per person and thing, never the owner, and only a housemate (`validates_within_household`).
- **The shared model** declares `include Shareable` and `shared_through :recipe_shares`. That gives it `shared_with?(profile)`, the people it's shared with, `people_with_access` (its owner and them: whom a live change is pushed to), and two hooks it may fill in:
  - `on_shared` and `on_unshared` redraw the calendar for the new reader, make a grocery list live for them, or write the file's trail.
- **One service** shares or stops sharing (`Shares::Create`, `Shares::Destroy`). It saves the share, tells the person (a notification, pushed to their devices), and runs the hook.
- **One controller and one modal** serve every kind. The routes' `shareable` concern names the kind, the modal is worded per kind through i18n, and only the owner may open it.

What a sharee may do is the thing's own policy. A shared recipe can be edited by its sharee, but not deleted. A shared file can be seen and downloaded, nothing more. A series shared with someone shows on their calendar, and they can change its days but not delete it. The policy matrix test holds all of it.

**Collections** group a few series to share as one thing (Healthcare calls them therapies). Whoever a collection is shared with sees its series, and the supplies bought for them.

## Linking calendars

Two housemates **link** (`Link`): one asks, the other accepts or declines, from the Links page or from the bell. Then each sees the other's calendar, as far as the other lets them.

**A grant per kind of item** (`LinkGrant`, one per kind of series: tasks, appointments, medications…) says what one lets the other do:

| Action | Levels | Default |
|---|---|---|
| Read | off · on | on |
| Write (change a day) | off · ask · on | ask |
| Create (add to my calendar) | off · ask · on | ask |
| Delete | off · ask · on | ask |

Turning reading off turns the rest off. Each grant is set with a row of pills on the Links page, and the other housemate is told about the change once.

The defaults apply when the link is accepted. A kind of item added to the app later is off on the links made before it: nobody agreed to share it, so it stays hidden until its owner turns it on, and the first tap saves its grant.

**Where the grants act:**
- **Reading** is a branch of `Event.accessible_by`. The calendar, home and its statistics, reminders and the assistant therefore all see a partner's items without knowing about links.
- **Writing, creating and deleting** are policy questions (`writable?`, `creatable?`, `deletable?` in `EventAuthorizable`), answered by `Links::Permissions` and memoized per request.
- **Cards** show a partner's item with its owner's name, a toggle that is locked where the grant says off, and a menu to delete the day or the series where it says on or ask.
- **A day's form** opens read-only where one may only read. A new item can be put on a partner's calendar ("On whose calendar") where the grant allows creating.

**An explicit share outranks a link.** A series shared outright can be changed without asking, even where a grant says "ask".

## "Ask": a change that waits for its owner

Where a grant says **ask**, the action isn't refused: it is **held** as a `LinkApproval`.
- **Holding:** right after authorizing, `LinkApprovable#held_for_approval?` keeps what would have been done. That covers the form's changes, the day, and which action it was (update, complete, delete…). The day is its date and, for a series taken several times a day, the time of its dose, so asking about the morning dose and then the evening one makes two requests, and approving one acts on that dose alone. Asking again about the same dose and action refreshes the request. The asker is told "Asked Alice to OK it".
- **Answering:** the owner is told through the bell and the Links page, and approves or declines there (`Links::Approvals::Decide`).
- **Applying:** approving runs the change **as the owner**, through the same code a direct change takes: the same `FormSave`, `complete!` or `Occurrences::Destroy`, or the assistant's own operation when the assistant asked (`Links::Approvals::Apply`).
- **Staleness:** if the day changed after it was asked about, the approval says so. Both the day's `updated_at` and its series' count.
- **Failing:** an approved request that can no longer be done keeps why as a reason (`LinkApproval#failure`: the thing is gone, it changed, or it is no longer allowed), not as words, since the asker and the owner may read different languages; each page words it for its reader. A change that no longer saves is also reported, because it passed its checks when it was asked for.
- **Withdrawing and expiry:** the asker can take a request back while it waits, and it expires after 30 days.
- **Cancelling:** when the owner deletes what a request is about, the request is cancelled and its Approve goes. Deleting a series cancels everything asked about it; deleting a day or a dose cancels what was asked about that day or dose, except a request to delete the whole series, which can still be done.

The menu's Links entry shows a count of what waits for an answer, and it stays live (`Links::Broadcaster`).

## Two people editing the same thing

Whatever more than one person can edit keeps a version and who saved it last: a series and its days, a recipe, a collection, a grocery list and its items, a therapy's purchases, the household's conversation.
- **The version** is the table's `lock_version`. Rails checks it on every update and moves it on, and refuses an update made from an older copy, undoing the whole save.
- **Who saved it** is `updated_by`, which a save names with `edited_by(profile)`: a form's save, and a press too (a day's circle, a grocery item's tick, settling "Needs attention"), so a form a press crossed can name who pressed. A save that names nobody leaves nobody named, so the name is never the wrong person's.
- **What it holds moves it too.** A change to a day's or a series' own fields, its times of the day or a lab result's values moves the version of the day or series it describes.
- **A form carries the version it was drawn at.** A save after someone else's is refused on the form, which says who saved meanwhile (or that it was oneself in another window). The form also says which fields were typed in it (`typed_fields_controller.js`, `EditedTogether::TypedFields`), and comes back with what was typed in those over what the other person saved; it now carries the new version, so saving again keeps both (`edit_as`). A day's form carries its series' version too (see [the calendar](calendar.md#saving-this-day-or-the-whole-series)).
- **A write that isn't an edit leaves it**: a conversation's latest message, what a done day keeps when its series changes, and where a series' days with nothing stored start.
- **Anywhere a crossed write isn't a form's**, it is answered with a toast saying someone saved a change a moment ago, and the page is brought up to date.

## Removing a person

Removing someone ends their links and their requests, and deletes the shares made to them. What they shared with others goes with them: it was theirs. What they last saved of a housemate's stays, saved by nobody.

---

Using it: [People](../guide/people.md)
