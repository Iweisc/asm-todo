# asm-todo

An issue tracker for teams in the style of Linear, written entirely in x86-64 assembly for Linux. No libc, no libraries, only raw syscalls. Every layer is hand-written: the WebSocket server, the Noise encryption and the crypto under it, the journaled database, the sync engine, the Wayland client, the rasterizer and the anti-aliased font.

- `todo-server` holds accounts, teams and their issues, and pushes every change to everyone viewing the same team.
- `todo-client` is a native Wayland window. It speaks the Wayland wire protocol over the compositor socket, draws every pixel into shared memory, and keeps one encrypted connection to the server.

## Build and run

Needs `nasm`, `ld` and `make`.

```
make          # builds build/todo-server and build/todo-client
make test     # crypto test vectors
make preview  # renders every text style and icon to build/preview.ppm
make lint     # function length, file length and function comments
make run      # starts the server with ./issues.db, opens a window, stops the server on close
```

Or run them separately:

```
build/todo-server [database-path] [ip:port]       # defaults: ./issues.db, 127.0.0.1:8080
build/todo-client <server-key> [ip:port]
```

`CONTRIBUTING.md` has the rules for changes. CI runs the build, the tests and the lint on every pull request.

The server prints its public key at startup and writes it to `<database-path>.pub`. The client needs that key and refuses any server that can't prove it holds the matching private key.

## Using it

Sign up or log in, then create a team. Its identifier (like `ENG`) prefixes issue IDs like `ENG-12`. Owners invite people by username from the sidebar and can remove them. Other members can leave.

Issues have a status (Backlog, Todo, In Progress, Done, Canceled), a priority, an assignee, a project, up to 16 labels, a description and comments. The list groups them by status, and the board shows a column per status. The sidebar switches between all issues, active ones, the backlog, your own issues and a single project. The filter bar narrows any of these to one label or project.

Drag a card on the board to another column to change its status. Esc while dragging puts it back.

Clicking an issue opens it. Click its title or description to edit them, and use the properties on the right to change the rest. Comments show up live for everyone viewing the issue.

Keys, when no text field has focus:

| Key | Does |
| --- | --- |
| `Ctrl+K` | command menu: every action, view and team, filtered as you type |
| `C` | new issue |
| `J` / `K`, arrows | move the selection. Left and right change board columns |
| `Enter` | open the selected issue |
| `S` `P` `A` `L` `M` | status, priority, assignee, labels, project |
| `Ctrl+B` | switch between list and board |
| `Esc` | close the issue, menu or dialog |

In menus, typing filters and Enter picks. In the label and project menus, typing a new name offers to create it. In the new issue dialog, Tab moves between title and description and Ctrl+Enter creates the issue. In comments, Enter sends and Shift+Enter adds a line. The keyboard layout is US QWERTY.

Changes made while the server is unreachable show up right away and are sent once the client reconnects.

## Security

- Transport: WebSocket carrying `Noise_NK_25519_ChaChaPoly_SHA256`. The client pins the server's static key, every connection gets fresh ephemeral keys, and any forged, replayed or reordered message closes the connection.
- Passwords: PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 16-byte salt per user. Hashing runs in slices between events, so logins never stall the server. Logins with an unknown username are hashed against a dummy salt, so response time doesn't reveal which usernames exist.
- Sessions: 256-bit random tokens, stored only as SHA-256 hashes, valid for 30 days, compared in constant time. Logging out revokes the session on every connection using it.
- Limits: 10 password checks per IP per minute, 5 failed attempts per connection, 16 connections per IP, 30 seconds to log in, 90 seconds idle. Clients that don't read their messages get disconnected instead of buffered without bound.
- Authorization: every operation checks team membership on the server, and every field is validated there. Only owners can add or remove members. Removed members stop receiving updates immediately and are unassigned from the team's issues.
- Storage: the database and its journal are created with mode 0600. The database holds the server's private key.

## Storage

The database is a snapshot plus a journal next to it (`issues.db.log`). Every change is appended to the journal as a checksummed batch and fdatasynced before anyone hears about it. On startup the server replays the journal over the snapshot, drops a torn last batch, then writes a fresh snapshot (temp file, fsync, rename, directory fsync) and starts a new journal. It also compacts once the journal passes 8 MB. A generation number in both files keeps a journal from being replayed over the wrong snapshot.

## Protocol

After `GET /sync` upgrades to WebSocket, the client sends Noise message 1 and the server replies with message 2. Every binary frame after that is one encrypted message whose first byte is its type. `src/common/config.inc` lists every message and field.

Sync works like this:

- Each team has a sequence number that goes up with every change. `SUBSCRIBE` returns the team's labels and projects, then a snapshot of its issues at the current sequence. Every change after that arrives as an `EVENT` with the next number. A client that sees a gap asks for a fresh snapshot.
- Descriptions and comments aren't in the snapshot. `OPEN_ISSUE` fetches them for one issue, and events keep the open issue current.
- Clients number their changes 1, 2, 3 per session. The server applies them in order and remembers the last one per session, so a change resent after a dropped connection is acknowledged without being applied twice.
- The client keeps the server's state and its own unacknowledged changes apart, and shows the two merged. That's how offline edits appear immediately and how a rejected change disappears cleanly.

## Layout

- `src/common/crypto/` has SHA-256, SHA-1, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305 and X25519.
- `src/common/noise.asm` has the Noise handshake and transport.
- `src/common/ws.asm` and `src/common/wire.asm` have WebSocket framing and the message reader and writers.
- `src/server/db.asm` has the tables, the journal and snapshots.
- `src/server/conn.asm` has the event loop's connections: HTTP upgrade, handshake, framing and buffered writes.
- `src/server/handlers.asm` has accounts and sessions. `teams.asm` has teams and members. `issues.asm` has snapshots, events and every change to issues, labels and projects.
- `src/client/net.asm` has the connection state machine, keepalive and reconnect.
- `src/client/sync.asm` has the client's copy of the team, the pending changes, and the merged view.
- `src/client/wayland.asm` has the window. `draw.asm`, `text.asm`, `font.asm` and `icons.asm` have the rasterizer, the anti-aliased stroke font and the icons.
- `src/client/ui.asm` has the client's state and list logic, `input.asm` the mouse and keyboard, `widgets.asm` fields, buttons and menus, and `views.asm` the screens.
- `tests/crypto_test.asm` checks the crypto against published test vectors. `tests/font_preview.asm` renders the font and icons for a look.
