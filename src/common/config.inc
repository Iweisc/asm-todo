; Shared between the server and the client, so both agree on the protocol.

%define DEFAULT_ADDR_BE     0x0100007F          ; 127.0.0.1, network byte order
%define DEFAULT_PORT        8080

; --- limits ---
%define USERNAME_MIN        3
%define USERNAME_MAX        32
%define PASSWORD_MIN        8
%define PASSWORD_MAX        128
%define TEAMNAME_MAX        32
%define TEAM_KEY_MIN        2
%define TEAM_KEY_MAX        5                   ; A-Z, the "ENG" in ENG-12
%define TITLE_MAX           120
%define DESC_MAX            1500
%define COMMENT_MAX         500
%define MESSAGE_MAX         500
%define CHAT_HISTORY        100                 ; a conversation opens with its newest messages
%define LABEL_SLOTS         16                  ; per team, so an issue's labels fit a u16
%define LABEL_NAME_MAX      24
%define PROJECT_SLOTS       16                  ; per team, numbered 1-16, 0 is "no project"
%define PROJECT_NAME_MAX    32
%define CHANNEL_SLOTS       16                  ; per team, besides #general, numbered 1-16
%define CHANNEL_NAME_MAX    24
%define CHANNEL_PEER        0x80000000          ; + slot, a channel where a conversation's peer goes
%define TEAM_ISSUE_MAX      1000
%define ISSUE_COMMENT_MAX   100
%define TEAM_MEMBER_MAX     64
%define USER_TEAM_MAX       32
%define IMAGE_MAX           8388608             ; bytes in one PNG
%define IMAGE_SIDE_MAX      16384               ; pixels on either side
%define IMAGE_PIXELS_MAX    16777216            ; width * height
%define IMAGE_PART          60000               ; bytes of an image per message, both ways

; OWASP's 2023 guidance for PBKDF2-HMAC-SHA256.
%define PBKDF2_ITERATIONS   600000

; --- WebSocket ---
%define WS_OP_BINARY        2
%define WS_OP_CLOSE         8
%define WS_OP_PING          9
%define WS_OP_PONG          10
; A WebSocket message carries exactly one Noise message, so Noise's limit applies.
%define WS_MAX_PAYLOAD      65535
%define NOISE_TAG           16
%define APP_MAX             (WS_MAX_PAYLOAD - NOISE_TAG)
%define NOISE_MSG1_LEN      48                  ; e (32) + tag of an empty payload
%define NOISE_MSG2_LEN      48

; --- application messages: first byte is the type ---
; str is a u8 length and bytes, str16 a u16 length and bytes.

; client -> server
%define MSG_REGISTER        1                   ; str username, str password
%define MSG_LOGIN           2                   ; str username, str password
%define MSG_RESUME          3                   ; token[32]
%define MSG_LOGOUT          4
%define MSG_CHANGE_PASSWORD 5                   ; str current password, str new password
%define MSG_CREATE_TEAM     16                  ; str key, str name
%define MSG_ADD_MEMBER      17                  ; u32 team, str username
%define MSG_REMOVE_MEMBER   18                  ; u32 team, u32 user (yourself = leave)
%define MSG_SUBSCRIBE       19                  ; u32 team
%define MSG_OPEN_ISSUE      20                  ; u32 issue, 0 to close it
%define MSG_OPEN_CHAT       21                  ; u32 peer: 0 for #general, CHANNEL_PEER + slot for another channel,
                                                ; a member for a DM, -1 to close it
%define MSG_SET_ROLE        22                  ; u32 team, u32 user, u8 role. Owners only, a team keeps one owner.
%define MSG_RENAME_TEAM     23                  ; u32 team, str name. Owners only.
%define MSG_SET_CHANNEL     24                  ; u32 team, u8 slot (0 makes a new one), str name (empty deletes it).
                                                ; Any member makes one, its maker or an owner changes it.
%define MSG_EDIT_MESSAGE    25                  ; u32 team, u32 message, str16 text. Only its author.
%define MSG_DELETE_MESSAGE  26                  ; u32 team, u32 message. Its author, or an owner in a channel.
%define MSG_UPLOAD_IMAGE    27                  ; u32 team, u32 peer (as in OPEN_CHAT, 0 for a comment), u32 bytes,
                                                ; u16 width, u16 height. Starts a PNG for the next message or comment.
                                                ; Any of the user's images not attached to anything yet are dropped.
%define MSG_IMAGE_PART      28                  ; u32 image, str16 the next bytes of it
%define MSG_GET_IMAGE       29                  ; u32 image, u32 offset
%define MSG_OP              32                  ; u32 op number, u8 kind, u32 team, ...

; server -> client
%define MSG_AUTH_OK         129                 ; u32 user, str name, token[32], u32 last op
%define MSG_AUTH_FAIL       130                 ; str message
%define MSG_ERROR           131                 ; str message
%define MSG_TEAMS           132                 ; u8 n, n * (u32 id, u8 role, str key, str name)
%define MSG_SNAPSHOT        133                 ; u32 team, u32 seq, u8 first, u8 last, u16 n, n * issue
%define MSG_EVENT           134                 ; u32 team, u32 seq, u8 kind, ...
%define MSG_ACK             135                 ; u32 op number, u8 status
%define MSG_MEMBERS         136                 ; u32 team, u8 n, n * (u32 user, u8 role, u8 online, str name)
%define MSG_LOGGED_OUT      137
%define MSG_TEAM_META       138                 ; u32 team, LABEL_SLOTS * label, PROJECT_SLOTS * project
%define MSG_ISSUE_DETAIL    139                 ; u32 issue, str16 description, u8 n, n * comment
%define MSG_CHAT            140                 ; u32 team, message
%define MSG_CHAT_HISTORY    141                 ; u32 team, u32 peer, u8 n, n * message, oldest first
%define MSG_UNREAD          142                 ; u32 team, u8 n, n * u32 peer with messages not seen yet
%define MSG_PASSWORD_CHANGED 143                ; the user's other sessions are logged out
%define MSG_CHANNELS        144                 ; u32 team, u8 n, n * (u8 slot, u32 maker, str name)
%define MSG_CHAT_EDITED     145                 ; u32 team, message
%define MSG_CHAT_DELETED    146                 ; u32 team, u32 message
%define MSG_IMAGE           147                 ; u32 image, u32 bytes, u32 offset, str16 data. 0 bytes if it can't be had.
%define MSG_UPLOAD_READY    148                 ; u32 image, u32 bytes received so far, after UPLOAD_IMAGE or each part

; An issue on the wire, without its description:
;   u32 id, u32 number, u8 status, u8 priority, u32 assignee, u8 project,
;   u16 labels, u32 creator, u32 created, u32 updated, str title
; A label or project: u32 color, str name. An empty name is an unused slot.
; A comment: u32 id, u32 author, u32 created, str16 text, u8 edited, image
; A message: u32 id, u32 from, u32 to (a peer, as in OPEN_CHAT), u32 created, str16 text, u8 edited, image
; An image: u32 id, u16 width, u16 height, all 0 for none
; Times are unix seconds.

; MSG_OP kinds and their extra fields
%define OP_CREATE_ISSUE     1                   ; u8 status, u8 priority, u32 assignee, u8 project, u16 labels, str title, str16 description
%define OP_SET_FIELD        2                   ; u32 issue, u8 field, value
%define OP_DELETE_ISSUE     3                   ; u32 issue
%define OP_COMMENT          4                   ; u32 issue, str16 text, u32 image or 0. Text can be empty with an image.
%define OP_SET_LABEL        5                   ; u8 slot, u32 color, str name (empty deletes it)
%define OP_SET_PROJECT      6                   ; u8 slot (1-16), u32 color, str name (empty deletes it)
%define OP_MESSAGE          7                   ; u32 to (a peer, as in OPEN_CHAT), str16 text, u32 image or 0.
                                                ; Text can be empty with an image.
%define OP_EDIT_COMMENT     8                   ; u32 comment, str16 text. Only its author.
%define OP_DELETE_COMMENT   9                   ; u32 comment. Its author or a team owner.

; OP_SET_FIELD fields and their values
%define FIELD_STATUS        1                   ; u32
%define FIELD_PRIORITY      2                   ; u32
%define FIELD_ASSIGNEE      3                   ; u32 user, 0 for nobody
%define FIELD_PROJECT       4                   ; u32
%define FIELD_LABELS        5                   ; u32 bitmask
%define FIELD_TITLE         6                   ; str
%define FIELD_DESCRIPTION   7                   ; str16

; MSG_EVENT kinds
%define EV_ISSUE            1                   ; issue, created or changed
%define EV_DESCRIPTION      2                   ; u32 issue, u32 updated, str16 description
%define EV_DELETED          3                   ; u32 issue
%define EV_COMMENT          4                   ; u32 issue, comment
%define EV_LABEL            5                   ; u8 slot, label. Deleting one clears it from every issue.
%define EV_PROJECT          6                   ; u8 slot, project. Deleting one clears it from every issue.
%define EV_COMMENT_EDITED   7                   ; u32 issue, comment
%define EV_COMMENT_DELETED  8                   ; u32 issue, u32 comment

; MSG_ACK status
%define ACK_OK              0
%define ACK_GONE            1                   ; the issue no longer exists
%define ACK_FORBIDDEN       2
%define ACK_INVALID         3
%define ACK_FULL            4

; Issue status, in workflow order
%define STATUS_BACKLOG      0
%define STATUS_TODO         1
%define STATUS_IN_PROGRESS  2
%define STATUS_DONE         3
%define STATUS_CANCELED     4
%define STATUS_COUNT        5

; Issue priority. 0 sorts last, so "none" sits below "low".
%define PRIO_NONE           0
%define PRIO_URGENT         1
%define PRIO_HIGH           2
%define PRIO_MEDIUM         3
%define PRIO_LOW            4
%define PRIO_COUNT          5

%define ROLE_OWNER          1
%define ROLE_MEMBER         2
