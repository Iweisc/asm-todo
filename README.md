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

Sign up or log in, then create a team. "Change password" in the command menu changes yours and logs out your other sessions. Its identifier (like `ENG`) prefixes issue IDs like `ENG-12`. Owners invite people by username from the sidebar and can remove them. Other members can leave.

Issues have a status (Backlog, Todo, In Progress, Done, Canceled), a priority, an assignee, a project, up to 16 labels, a description and comments. The list groups them by status, and the board shows a column per status. The sidebar switches between all issues, active ones, the backlog, your own issues and a single project. The filter bar narrows any of these by label, project, priority or assignee.

Drag a card on the board to another column to change its status. Esc while dragging puts it back.

Clicking an issue opens it. Click its title or description to edit them, and use the properties on the right to change the rest. Comments show up live for everyone viewing the issue. Hover over your own comment to edit or delete it. Team owners can delete anyone's.

Each team has a `#general` channel, and clicking a member in the sidebar opens a direct conversation with them. Messages arrive live, and a dot marks conversations with messages you haven't seen yet, even after a restart. Opening a conversation loads its newest 100 messages. Messages can be up to 500 characters, and each server keeps the newest 32,768 across all teams.

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

Text fields work like any other app's: Shift with the arrows, Home or End selects, Ctrl moves by word, double-click selects a word and triple-click everything, and dragging selects. Ctrl+A, Ctrl+C, Ctrl+X and Ctrl+V select all, copy, cut and paste through the system clipboard. Ctrl+Backspace and Ctrl+Delete remove a word. Pasted text keeps to printable ASCII: curly quotes, dashes and the like become their plain versions.

Dates are shown in the local time zone, from `TZ` or `/etc/localtime`.

Changes and messages made while the server is unreachable show up right away and are sent once the client reconnects.

## Security

- Transport: WebSocket carrying `Noise_NK_25519_ChaChaPoly_SHA256`. The client pins the server's static key, every connection gets fresh ephemeral keys, and any forged, replayed or reordered message closes the connection.
- Passwords: PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 16-byte salt per user. Hashing runs in slices between events, so logins never stall the server. Logins with an unknown username are hashed against a dummy salt, so response time doesn't reveal which usernames exist.
- Sessions: 256-bit random tokens, stored only as SHA-256 hashes, valid for 30 days, compared in constant time. Logging out revokes the session on every connection using it. Changing a password needs the current one, hashes the new one with a fresh salt, and revokes every other session of the user. It counts against the same per-IP limit as logins.
- Limits: 10 password checks per IP per minute, 5 failed attempts per connection, 16 connections per IP, 30 seconds to log in, 90 seconds idle. Clients that don't read their messages get disconnected instead of buffered without bound.
- Authorization: every operation checks team membership on the server, and every field is validated there. Only owners can add or remove members. Removed members stop receiving updates and messages immediately and are unassigned from the team's issues. Direct messages only reach the two people in them.
- Storage: the database and its journal are created with mode 0600. The database holds the server's private key. The client's session file is mode 0600 in a 0700 directory, and is replaced by rename so a crash leaves the old one or the new one.

## Storage

The database is a snapshot plus a journal next to it (`issues.db.log`). Every change is appended to the journal as a checksummed batch and fdatasynced before anyone hears about it. On startup the server replays the journal over the snapshot, drops a torn last batch, then writes a fresh snapshot (temp file, fsync, rename, directory fsync) and starts a new journal. It also compacts once the journal passes 8 MB. A generation number in both files keeps a journal from being replayed over the wrong snapshot. Snapshots carry a format version: version 2 added a comment's edited mark, and the server still loads version 1 and saves it as 2.

## Protocol

After `GET /sync` upgrades to WebSocket, the client sends Noise message 1 and the server replies with message 2. Every binary frame after that is one encrypted message whose first byte is its type. `src/common/config.inc` lists every message and field.

Sync works like this:

- Each team has a sequence number that goes up with every change. `SUBSCRIBE` returns the team's labels and projects, then a snapshot of its issues at the current sequence. Every change after that arrives as an `EVENT` with the next number. A client that sees a gap asks for a fresh snapshot.
- Descriptions and comments aren't in the snapshot. `OPEN_ISSUE` fetches them for one issue, and events keep the open issue current.
- Comments are changed with `EDIT_COMMENT` (its author only) and `DELETE_COMMENT` (its author or a team owner), which reach viewers of the issue as `COMMENT_EDITED` and `COMMENT_DELETED` events. A comment carries an edited mark once changed.
- Messages are sent as changes too, but they aren't events and don't move the sequence number. `SUBSCRIBE` also returns `UNREAD`, the conversations with messages the user hasn't seen. `OPEN_CHAT` fetches a conversation's newest messages and marks them seen, and `CHAT` delivers each new message to the connections allowed to read it.
- Clients number their changes 1, 2, 3 per session. The server applies them in order and remembers the last one per session, so a change resent after a dropped connection is acknowledged without being applied twice.
- The client keeps the server's state and its own unacknowledged changes apart, and shows the two merged. That's how offline edits appear immediately and how a rejected change disappears cleanly.

## Layout

- `src/common/crypto/` has SHA-256, SHA-1, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305 and X25519.
- `src/common/noise.asm` has the Noise handshake and transport.
- `src/common/ws.asm` and `src/common/wire.asm` have WebSocket framing and the message reader and writers.
- `src/server/db.asm` has the tables, the journal and snapshots.
- `src/server/conn.asm` has the event loop's connections: HTTP upgrade, handshake, framing and buffered writes.
- `src/server/handlers.asm` has accounts and sessions, and `password.asm` changing a password. `teams.asm` has teams and members. `issues.asm` has snapshots, events and every change to issues, labels and projects. `messages.asm` has the team channel, direct messages and seen marks.
- `src/client/net.asm` has the connection state machine, keepalive and reconnect.
- `src/client/sync.asm` has the client's copy of the team, the pending changes, and the merged view.
- `src/client/wayland.asm` has the window. `draw.asm`, `text.asm`, `shapes.asm`, `font.asm` and `icons.asm` have the rasterizer, the anti-aliased stroke font, the anti-aliased shapes and the icons.
- `src/client/ui.asm` has the client's state and list logic, `input.asm` the mouse and keyboard, `keymap.asm` the keyboard layout, `edit.asm` text field editing and selection, `clipboard.asm` copy and paste, `widgets.asm` fields, buttons and chips, `menu.asm` the command menu and the pickers, `views.asm` the screens, `sidebar.asm` the sidebar, `chat.asm` opening and drawing a conversation, `comments.asm` an issue's comments and editing them, `labels.asm` the dialog for renaming and deleting labels and projects, `account.asm` the change password dialog, and `dialogs.asm` opening and submitting the new issue and new team dialogs.
- `src/client/session.asm` remembers the server and login between runs, and `localtime.asm` reads the time zone.
- `tests/crypto_test.asm` checks the crypto against published test vectors. `tests/ui_test.asm` draws the client into memory and checks how it answers clicks, keys and the wheel. `tests/font_preview.asm` renders the font and icons for a look.
