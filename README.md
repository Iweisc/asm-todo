# asm-todo

An issue tracker for teams in the style of Linear, written entirely in x86-64 assembly for Linux. No libc, no libraries, only raw syscalls. Every layer is hand-written: the WebSocket server, the Noise encryption and the crypto under it, the journaled database, the sync engine, the Wayland client, the rasterizer and the anti-aliased font.

- `todo-server` holds accounts, teams, their issues and their messages, and pushes every change to everyone viewing the same team.
- `todo-client` is a native Wayland window. It speaks the Wayland wire protocol over the compositor socket, draws every pixel into shared memory, and keeps one encrypted connection to the server.

## Build and run

Needs `nasm`, `ld` and `make`.

```
make          # builds build/todo-server and build/todo-client
make test     # crypto test vectors and UI checks
make preview  # renders every text style and icon to build/preview.ppm
make lint     # function length, file length and function comments
make run      # starts the server with ./issues.db, opens a window, stops the server on close
```

Or run them separately:

```
build/todo-server [database-path] [ip:port]       # defaults: ./issues.db, 127.0.0.1:8080
build/todo-client [<server-key> [ip:port]]
```

`CONTRIBUTING.md` has the rules for changes. CI runs the build, the tests and the lint on every pull request.

The server prints its public key at startup and writes it to `<database-path>.pub`. The client needs that key and refuses any server that can't prove it holds the matching private key. It remembers the last server and your login in `$XDG_STATE_HOME/asm-todo/session` (or `~/.local/state/asm-todo/session`), so after the first run a bare `todo-client` reconnects and skips the login. Logging out forgets the login but keeps the server.

## Using it

Sign up or log in, then create a team. Its identifier (like `ENG`) prefixes issue IDs like `ENG-12`.

Your name at the top of the sidebar, or "Account settings" in the command menu, opens your account. Profile has your user number, when you joined and how many teams you're on, and Delete account, which needs your password and asks first. You can't delete your account while you're the last owner of a team. Deleting it takes you off every team and deletes your direct messages. Issues, comments and channel messages you wrote stay, and the audit log calls you "Deleted user". Password and sessions ("Change password" in the command menu) changes your password, which logs out your other sessions, and lists your sessions with when each signed in and last connected, Log out on every other one, and Log out everywhere else. Teams ("All teams" in the command menu) lists every team you're on with your role, its members and open issues, and links to open it, open its settings or leave it. It has New team too.

The gear that shows when you hover over the team's sidebar row opens its settings, on the Overview tab: how many members there are and how many have the team open, open and done issues, issues by status, who holds each role, and the newest audit log entries for those who can see the log. Owners also get Delete team there, which needs the team's key typed, asks first, and deletes its issues, messages, channels and images. A team has owners and members, and members get permissions from roles. Everyone sees the member list, with a search box that matches names and nicknames, and can leave, except the last owner. What else shows depends on the permissions you have: renaming the team, inviting people by username, the Roles tab, the ban list with Unban, the audit log and the AutoMod tab. The audit log has the newest 50 invites, removals, bans, unbans, timeouts, role and nickname changes, channel and AutoMod settings, messages AutoMod blocked, ownership transfers, renames and deletions of other people's posts, with who did it, when and why.

The Roles tab lists the team's roles, highest first, and `@everyone`, which every member has. A team can have 16 roles, each with a name, a color and a switch for each of 15 permissions: Administrator, rename the team, manage roles, manage channels, invite, kick, ban, time out, delete others' messages, view the audit log, change others' nicknames, change your own, manage AutoMod, view channels and send messages. Administrator gives every permission and skips channel overrides. New teams start with a Moderator role that can invite, kick, ban, time out, delete messages, view the audit log and change nicknames, and `@everyone` can view channels, send messages and change their own nickname. A member has `@everyone`'s permissions plus those of all their roles, and owners have them all. Their rank is their highest role's place in the list. Managing roles only reaches roles below your own highest one, and only hands out permissions you have. Move up and Move down reorder them.

"Manage" on a member opens their page, and on yourself lets you change your own nickname. Depending on your permissions and as long as they rank below you, you can set their nickname of up to 32 characters, switch their roles on and off, make them an owner or hand them the team with Transfer ownership, which makes you a member (owners only), time them out for 60 seconds, 5 or 10 minutes, an hour, a day or a week, end a timeout early, kick them, or ban them, which also keeps them from being invited back until they're unbanned. A ban can also delete their messages in the team from the last hour, day or week. A reason typed on the page goes in the audit log. Owners can't be timed out, and neither can administrators. A timed out member can still read everything and leave, but can't post, comment, change issues or make channels until it ends. Remove, Leave, Kick, Ban, Transfer ownership and Delete role ask first. The "+" next to Direct messages opens the same dialog at the invite box, for anyone who can invite.

The AutoMod tab holds the team's blocked words, one per line, up to 1,000 characters, and a timeout for anyone who uses one. A word matches whole and ignoring case, and a `*` at either end lets it run on into the rest of a word, so `spam*` catches "spammer". A message that matches, posted or edited in a channel, isn't stored and goes in the audit log. Members who can manage AutoMod aren't checked.

Issues have a status (Backlog, Todo, In Progress, Done, Canceled), a priority, an assignee, a project, up to 16 labels, a description and comments. The list groups them by status, and the board shows a column per status. The sidebar switches between all issues, active ones, the backlog, your own issues and a single project. The filter bar narrows any of these by label, project, priority or assignee.

Drag a card on the board to another column to change its status. Esc while dragging puts it back.

Clicking an issue opens it, and right-clicking one opens a menu of what you can do to it. Click its title or description to edit them, and use the properties on the right to change the rest. Comments show up live for everyone viewing the issue. Hover over your own comment to edit or delete it. Members who can delete others' messages can delete anyone's.

Each team has a `#general` channel, and anyone in it can make up to 16 more with the "+" next to Channels. "Edit channel" in a channel's header renames or deletes it, for whoever made it and for anyone who can manage channels. The same dialog sets its slowmode, from 5 seconds to an hour between messages per member, and its overrides: for `@everyone` and each role, whether viewing, sending and deleting others' messages there is allowed, denied, or left to the role's permissions. `@everyone`'s override applies first, then the member's roles' together, where an allow beats a deny. A channel you can't view doesn't show, and in one you can't send in the message box says so. Members who can delete others' messages there aren't held by slowmode. Deleting one deletes its messages. Clicking someone under Direct messages opens a conversation with them. Messages arrive live, and a dot marks conversations with messages you haven't seen yet, even after a restart. Opening a conversation loads its newest 100 messages. Messages can be up to 500 characters, and each server keeps the newest 32,768 across all teams.

Hover over your own message to edit or delete it. Members who can delete others' messages can delete anyone's in a channel, but not in someone else's direct conversation. Edited messages say so.

Type `@` in a message, comment or description to mention someone on the team. The members whose names start with what follows come up by the caret. The arrows move through them, Enter, Tab or a click puts the name in, and Esc closes the list. Mentions of members show in color, and yours on a highlight too. A channel with a message you haven't seen that mentions you gets an `@` instead of the dot, even after a restart. Mentions in comments and descriptions are only highlighted.

Paste an image into the message or comment box with Ctrl+V, drop one on it, or pick one with the image button beside the send button. A screenshot, an image copied from a browser, and a PNG file from a file manager all work. The button opens zenity, kdialog or yad, whichever is installed. It uploads while you type, shows above the box with an X to remove it, and goes out with the text on Enter or the send button, or on its own. Click an image to see it as big as the window allows, and click or press Esc to close it. Images are PNGs up to 8 MB and 16 megapixels. Deleting the message or comment deletes its image.

Keys, when no text field has focus:

| Key | Does |
| --- | --- |
| `Ctrl+K` | command menu: every action, view and team, and issues by title or ID, filtered as you type |
| `C` | new issue |
| `J` / `K`, arrows | move the selection. Left and right change board columns |
| `Enter` | open the selected issue |
| `S` `P` `A` `L` `M` | status, priority, assignee, labels, project |
| `Ctrl+B` | switch between list and board |
| `Ctrl+C` | copy the selected issue's ID |
| `Esc` | close the issue, conversation, menu or dialog |

In menus, typing filters and Enter picks. In the label and project menus, typing a new name offers to create it. "Manage labels and projects" in the command menu renames and deletes them. Deleting one takes it off every issue. In the new issue dialog, Tab moves between title and description and Ctrl+Enter creates the issue. In comments and messages, Enter sends and Shift+Enter adds a line. In an open conversation, typing anywhere goes to the message box.

The keyboard layout comes from the compositor, so AZERTY, QWERTZ, Dvorak and others type what their keys say, and letter shortcuts follow the letter rather than the key's position. Characters outside ASCII can't be typed yet.

Text fields work like any other app's: Shift with the arrows, Home or End selects, Ctrl moves by word, double-click selects a word and triple-click everything, and dragging selects. Ctrl+A, Ctrl+C, Ctrl+X and Ctrl+V select all, copy, cut and paste through the system clipboard. Ctrl+Backspace and Ctrl+Delete remove a word. Ctrl+Z undoes, a word at a time while typing, and Ctrl+Y or Ctrl+Shift+Z redoes. Password fields keep no history. Pasted text keeps to printable ASCII: curly quotes, dashes and the like become their plain versions.

Dates are shown in the local time zone, from `TZ` or `/etc/localtime`.

Changes and messages made while the server is unreachable show up right away and are sent once the client reconnects.

## Security

- Transport: WebSocket carrying `Noise_NK_25519_ChaChaPoly_SHA256`. The client pins the server's static key, every connection gets fresh ephemeral keys, and any forged, replayed or reordered message closes the connection.
- Passwords: PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 16-byte salt per user. Hashing runs in slices between events, so logins never stall the server. Logins with an unknown username are hashed against a dummy salt, so response time doesn't reveal which usernames exist.
- Sessions: 256-bit random tokens, stored only as SHA-256 hashes, valid for 30 days, compared in constant time. Logging out revokes the session on every connection using it. Changing a password needs the current one, hashes the new one with a fresh salt, and revokes every other session of the user. It counts against the same per-IP limit as logins. A user sees their sessions that haven't expired and can revoke any other one, or all of them. Deleting an account needs its password, counts against the same limit, is refused while the user is the last owner of a team, and revokes every session.
- Limits: 10 password checks per IP per minute, 5 failed attempts per connection, 16 connections per IP, 30 seconds to log in, 90 seconds idle. Clients that don't read their messages get disconnected instead of buffered without bound.
- Authorization: every operation checks team membership and the member's permissions on the server, and every field is validated there. Only owners make owners, transfer ownership or delete a team, and a team always keeps one. Acting on a member or a role needs to rank above them, and a role can't be given permissions its editor doesn't have. The server refuses anyone banned from a team as a member of it. Timed out members are refused every change until the timeout ends. Removed and banned members stop receiving updates and messages immediately and are unassigned from the team's issues. The ban list, the audit log and the AutoMod rules only go to members with the permission for them. A channel's messages, unread marks and images only go to members who can view it, and its slowmode and AutoMod are checked on the server. Direct messages only reach the two people in them.
- Storage: the database and its journal are created with mode 0600. The database holds the server's private key. The client's session file is mode 0600 in a 0700 directory, and is replaced by rename so a crash leaves the old one or the new one.

## Storage

The database is a snapshot plus a journal next to it (`issues.db.log`). Every change is appended to the journal as a checksummed batch, and the changes from one turn of the event loop share a single fdatasync. Replies wait for it, so nobody hears about a change before it's on disk. On startup the server replays the journal over the snapshot, drops a torn last batch, then writes a fresh snapshot (temp file, fsync, rename, directory fsync) and starts a new journal. It also compacts once the journal passes 8 MB. A generation number in both files keeps a journal from being replayed over the wrong snapshot. Snapshots carry a format version: version 2 added a comment's edited mark, version 3 added channels and a message's edited mark, version 4 added images, version 5 added a member's timeout and roles, bans, the audit log, roles, channel settings, nicknames and AutoMod rules, and version 6 added when an account was made and when a session last connected. The server still loads versions 1 to 5 and saves them as 6. Accounts from before version 6 have no join date. The audit log keeps the newest 16,384 entries across all teams.

Images are files in a directory beside the database (`issues.db.images/`), one per image, named by its id and created with mode 0600. The database has a row for each, written when its upload starts. A file only counts once the row says every byte arrived, and the last part is fdatasynced first. Uploads the server stopped in the middle of are deleted on startup.

## Protocol

After `GET /sync` upgrades to WebSocket, the client sends Noise message 1 and the server replies with message 2. Every binary frame after that is one encrypted message whose first byte is its type. `src/common/config.inc` lists every message and field.

Sync works like this:

- Each team has a sequence number that goes up with every change. `SUBSCRIBE` returns the team's labels and projects, then a snapshot of its issues at the current sequence. Every change after that arrives as an `EVENT` with the next number. A client that sees a gap asks for a fresh snapshot.
- Descriptions and comments aren't in the snapshot. `OPEN_ISSUE` fetches them for one issue, and events keep the open issue current.
- Comments are changed with `EDIT_COMMENT` (its author only) and `DELETE_COMMENT` (its author or a member who can delete others' messages), which reach viewers of the issue as `COMMENT_EDITED` and `COMMENT_DELETED` events. A comment carries an edited mark once changed.
- Messages are sent as changes too, but they aren't events and don't move the sequence number. `SUBSCRIBE` also returns `CHANNELS` and `UNREAD`, the conversations with messages the user hasn't seen and the channels among them where one of those mentions the user. `OPEN_CHAT` fetches a conversation's newest messages and marks them seen, and `CHAT` delivers each new message to the connections allowed to read it. A conversation is named by its peer: 0 for `#general`, `CHANNEL_PEER` plus a slot for another channel, or the other person.
- `REMOVE_MEMBER`, `BAN` and `TIMEOUT` carry a reason, `BAN` also how many seconds of the member's messages to delete, and `UNBAN` takes a ban back. `MEMBERS` says who's timed out until when, which roles each member has, and their nickname. `SUBSCRIBE` returns `ROLES`, and members with the permission for them get `BANS`, `AUDIT` and `AUTOMOD` too, all again after every change to them. A change refused because its sender is timed out is acknowledged with `ACK_TIMED_OUT`, one held back by slowmode with `ACK_SLOWMODE`, and one AutoMod blocked with `ACK_BLOCKED`.
- `SAVE_ROLE` makes, changes or deletes a role, or changes `@everyone`'s permissions, `MOVE_ROLE` moves one up or down, and `MEMBER_ROLES` sets which roles a member has. Everyone viewing the team gets the new `ROLES`, `MEMBERS` and `CHANNELS` after any of them. `NICKNAME` sets or clears a member's nickname, and `SET_AUTOMOD` the blocked words and their timeout.
- `SET_CHANNEL` makes, renames or deletes a channel, and `CHANNEL_SETTINGS` sets a channel's slowmode and overrides. Everyone viewing the team gets their own `CHANNELS`: the channels they can view, `#general` among them as slot 0, each with what they can do in it. `EDIT_MESSAGE` and `DELETE_MESSAGE` change a message, and its readers get `CHAT_EDITED` or `CHAT_DELETED`. These, `SET_ROLE`, `RENAME_TEAM`, the role and channel settings messages and the moderation messages aren't changes in the op queue, so they need a connection.
- An image is uploaded before the message or comment it goes with: `UPLOAD_IMAGE` gives its size and the conversation it's for, and the server answers each `IMAGE_PART` with `UPLOAD_READY` and the bytes it has, so one part is in flight at a time. The server checks the file starts as a PNG of the size it said. The message or comment then names the image's id, and only its uploader can attach it, once, in that conversation. `GET_IMAGE` downloads one a part at a time, for whoever can read what it's attached to. Messages and comments carry their image's id and size, so clients lay them out before downloading them.
- `ACCOUNT_INFO` asks for `ACCOUNT`: when the user joined, their sessions that haven't expired with when each signed in and last connected, and each of their teams' member count and open issues. `END_SESSION` logs out another session, or all of them. `DELETE_ACCOUNT` takes the password and is answered with `LOGGED_OUT`. `DELETE_TEAM` takes the team's key, and its members get a new `TEAMS`. `TRANSFER_OWNER` makes a member the owner and the sender a member. These aren't changes in the op queue either.
- Clients number their changes 1, 2, 3 per session. The server applies them in order and remembers the last one per session, so a change resent after a dropped connection is acknowledged without being applied twice.
- The client keeps the server's state and its own unacknowledged changes apart, and shows the two merged. That's how offline edits appear immediately and how a rejected change disappears cleanly.

## Layout

- `src/common/crypto/` has SHA-256, SHA-1, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305 and X25519.
- `src/common/noise.asm` has the Noise handshake and transport.
- `src/common/ws.asm` and `src/common/wire.asm` have WebSocket framing and the message reader and writers, and `src/common/mention.asm` what counts as a mention, so both sides agree.
- `src/server/db.asm` has the tables, the journal and snapshots.
- `src/server/conn.asm` has the event loop's connections: HTTP upgrade, handshake, framing and buffered writes.
- `src/server/handlers.asm` has accounts and sessions, and `password.asm` changing a password. `teams.asm` has teams, members and owners, `roles.asm` roles, permissions and ranks, `nicknames.asm` nicknames, `moderation.asm` bans, timeouts and the audit log, and `automod.asm` the blocked words and checking messages against them, `sessions.asm` the account's sessions and its teams' sizes, and `teardown.asm` deleting teams and accounts. `issues.asm` has snapshots, events and every change to issues, labels and projects. `messages.asm` has messages, editing them and seen marks, `channels.asm` the channels besides `#general` and every channel's slowmode, overrides and who can see it, and `images.asm` uploading, storing and serving images.
- `src/client/net.asm` has the connection state machine, keepalive and reconnect.
- `src/client/sync.asm` has the client's copy of the team, the pending changes, and the merged view.
- `src/client/wayland.asm` has the window. `draw.asm`, `text.asm`, `shapes.asm`, `font.asm`, `icons.asm` and `glyphs.asm` have the rasterizer, the anti-aliased stroke font, the anti-aliased shapes, the status, priority and avatar icons, and the line icons.
- `src/client/ui.asm` has the client's state and list logic, `input.asm` the mouse and keyboard, `keymap.asm` the keyboard layout, `edit.asm` text field editing and selection, `clipboard.asm` copy, paste and drops, `widgets.asm` fields, buttons, switches and chips, `menu.asm` the command menu and the pickers, `views.asm` the screens, `chips.asm` the label and project chips on rows and cards, `sidebar.asm` the sidebar, `chat.asm` opening and drawing a conversation, `comments.asm` an issue's comments and editing them, and the Edit and Delete links messages share, `labels.asm` the dialog for renaming and deleting labels and projects, `account.asm` and `accountpage.asm` the account dialog with its profile, password and sessions, and teams, `dialogs.asm` opening and submitting the new issue and new team dialogs, `members.asm` the team settings dialog and its member list, `overview.asm` its Overview tab, `dashboard.asm` its member pages and ban list, `audit.asm` the audit log, `access.asm` the team's roles and what they let us do, `rolepage.asm` the Roles and AutoMod tabs, `channel.asm` the channel list and its dialog with the slowmode and overrides, `chatedit.asm` editing and deleting messages, `undo.asm` undo and redo in text fields, `attach.asm` pasting, dropping and uploading an image, `pick.asm` the box buttons and the file dialog behind the image one, `thumbs.asm` downloading, caching and drawing images, and `mentions.asm` the list of members while a mention is typed, drawing mentions and the channels' `@` marks. `inflate.asm` and `png.asm` decode PNGs, scaled down as they're decoded.
- `src/client/session.asm` remembers the server and login between runs, and `localtime.asm` reads the time zone.
- `tests/crypto_test.asm` checks the crypto against published test vectors. `tests/server_test.asm` runs the server's connections and journal over a socketpair and checks that replies wait for the fdatasync. `tests/ui_test.asm` draws the client into memory and checks how it answers clicks, keys and the wheel, with the checks of messages in `tests/ui_messages.asm`, of the newer controls in `tests/ui_controls.asm`, of mentions in `tests/ui_mentions.asm`, of moderation in `tests/ui_moderation.asm`, of roles, nicknames, channel settings and AutoMod in `tests/ui_roles.asm`, and of the account dialog and the Overview in `tests/ui_account.asm`. `tests/png_test.asm` decodes the PNGs `tests/images/make_images.py` wrote, one for every color type, filter and kind of deflate block, and compares the pixels. `tests/font_preview.asm` renders the font and icons for a look.
