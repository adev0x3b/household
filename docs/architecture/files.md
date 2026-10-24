# Files

[Documentation](../README.md) › [Architecture](README.md)

The Files section keeps files of any size on the server: a lease, a scan, a holiday's photos. It is built the way enterprise file-sharing tools are, kept to what a household needs. A file is private to whoever uploaded it until they share it with a housemate or hand out a public link.

## One file

An `Upload` is first an upload in progress, then the file:
- its status goes uploading → processing → ready;
- `received_bytes` counts up to the `byte_size` it declared.

Its bytes live under `storage/files/<key>` (`Uploads::Storage`), outside Active Storage and outside the web root. The name the person gave it is cleaned (`Uploads::Filename`) and is what a download is called.

## Uploading in chunks, resumably

The protocol is built in, in the spirit of [tus](https://tus.io):

1. `POST /files` makes the row with the size declared. The household's quota (`Uploads::Quota`) is checked and that size reserved, under the household's row lock, so two uploads at once can't both take the last space (`Uploads::Create`).
2. `POST /files/:id/chunks` appends one chunk at the offset its `Upload-Offset` header names, under the row's lock (`Uploads::Append`). A wrong offset answers **409 with the right one**, so a client that lost track resumes from where the server is.
3. `GET /files/:id/progress` says where to resume after a lost connection.
4. The last chunk hands the file to `Uploads::FinishJob`. It checks the size, computes the SHA-256, reads the content type from the bytes rather than the name (Marcel), and marks it ready. That is the place a virus scan would go.

Chunks are 16 MB. The tunnel in front of the app refuses request bodies over 100 MB, and a chunk is small enough to resend cheaply.

The upload modal (`uploader_controller.js`, with the queue and its parts in `app/javascript/uploader`) shows each file's percentage, bytes sent, speed over the last 8 seconds and time left, and its row on the list follows. A phone pauses a page in the background, and Background Fetch takes no request bodies, so **a web page can't upload from a minimised browser**. The modal therefore:
- keeps the screen on while files go up (the Wake Lock API);
- doesn't count a connection lost in the background against its retries;
- tries a chunk again when the proxy answers for the app while it restarts (502, 503, 504), as for a lost connection;
- takes a last chunk refused because the file is already whole (its first answer lost on the way) as sent;
- says so when the server has given a file up while checking it, and starts it over when resumed;
- goes on by itself when the page is seen again.

Uploads nobody finished are swept after a day (`Uploads::SweepJob`). A file whose check stalled, because it failed or a restart lost the job, is checked again at each hourly sweep; one still unchecked a day after its last chunk is removed too, and its owner is told under the bell to upload it again.

## Downloading

Pressing Download is a POST to the file's downloads, posted outside Turbo: it puts the download on the file's trail and redirects to the file's bytes, which the browser saves. Only a person's press records a download: a download cut short and resumed asks again for the bytes alone, which changes nothing.

The bytes are `send_file` as an attachment, with `Cache-Control: private, no-store`, after the request is authorized. In production, Thruster serves them from the `X-Sendfile` header, ranges included, so a big download doesn't hold a Ruby process. The proxy in front doesn't buffer responses (`config/deploy.yml` turns kamal-proxy's response buffering off, or it would spool a whole file to disk before sending a byte), and Thruster's read and write deadlines are lengthened there too, since they bound the whole request and the whole response and 30 seconds is too little for a chunk over a slow link or an hour-long download. Each household has a quota, `FILES_QUOTA` in the destination's environment, and the declared size is reserved when an upload starts. After a deploy, a 200 MB upload through the tunnel, `curl -I` on a download and `curl -r 0-1023` for a 206 check all three.

## Sharing with a housemate

Sharing a file is an `UploadShare`, like every share (see [Sharing and links](sharing-and-links.md)). A file can only be shared once it is ready. The person it is shared with can see and download it, nothing else.

## Public links

A public link (`UploadLink`) lets someone with no account download one file.
- **The token is shown once.** The owner mints a link (`UploadLink.mint`) and sees its token that one time. The database keeps only the token's SHA-256.
- **Lifetime and downloads:** a link is good for 1, 7 or 30 days, and for 1, 5 or unlimited downloads (one by default).
- **Password:** optional, at least 8 characters. Ten wrong passwords revoke the link, on its trail. The owner can revoke it at any time.
- **The public page** (`/s/:token`) shows the file and a Download button. The press counts the download atomically (`#consume!`) and redirects to the bytes by a signed ticket, good for an hour **in the session that pressed** (a nonce that session keeps). An interrupted download resumes without spending the link again, while the ticket's address, passed on, opens nothing.
- **Limits:** the public page is rate-limited by address; an installation with uploads off (`UPLOADS=off`, the demo) makes no links.

## The trail

Every event in a file's life is an `UploadActivity`, which the owner reads on the file's page:
- an upload, a share, an unshare;
- a download, and by whom;
- a link made, revoked or used;
- a link refused, with the address;
- a link closed by too many wrong passwords.

## Live

When a file becomes ready or is renamed, its row is replaced for its owner and everyone it is shared with, and its page for its owner. Its row is removed when it goes (`Uploads::Broadcaster`).

## Quota

The admin sets what a household may keep, and whether anything new comes in at all, on `/admin/settings` (`Platform.files_quota`, `Platform.uploads?`); a destination's environment can start either elsewhere (`FILES_QUOTA`, `UPLOADS`, off on the demo: what is there is seen and downloaded, nothing is uploaded or linked). Removing a person deletes their files, the bytes after the transaction commits, along with their shares and links and what was shared with them.

---

Using it: [Files](../guide/files.md)
