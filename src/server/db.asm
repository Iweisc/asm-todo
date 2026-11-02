; The server's state: users, teams, memberships, issues, comments,
; sessions, messages and seen marks, held in fixed-size tables of slots.
;
; On disk it's a snapshot plus a journal. Handlers mark the rows they change
; with db_touch, and db_commit appends those rows to <db>.log as one batch and
; fdatasyncs it, so a change costs a few KB of writes instead of a full save.
; At startup the journal is replayed, then folded into a fresh snapshot.
;
; Snapshot: the 96-byte header (which includes the server's private key),
; then each table's slots up to its high-water mark. The header ran out of
; room for counts, so tables after the first HEADER_TABLES write theirs as a
; u32 just before their slots. Created 0600.
;
; Journal: "ATJ1", u32 generation, then batches of
;   u32 length, records, u32 FNV-1a of the records
; where a record is u8 table, u32 slot, the row, and every batch ends with
; the header record: 0xff and the header's first 64 bytes.
;
; Every snapshot bumps the generation, and a journal only replays onto the
; snapshot with its own generation. That makes a crash halfway through
; compaction harmless: a journal older than the snapshot gets ignored.

%define USER_ID         0
%define USER_NAME_LEN   4
%define USER_NAME       5               ; USERNAME_MAX bytes
%define USER_SALT       40              ; 16 bytes
%define USER_HASH       56              ; PBKDF2 output, 32 bytes
%define USER_SIZE       96

; Labels and projects live inside their team's row. A slot with an empty
; name is unused.
%define LABEL_COLOR     0
%define LABEL_NAME_LEN  4
%define LABEL_NAME      5               ; LABEL_NAME_MAX bytes
%define LABEL_SIZE      32
%define PROJ_COLOR      0
%define PROJ_NAME_LEN   4
%define PROJ_NAME       5               ; PROJECT_NAME_MAX bytes
%define PROJ_SIZE       40

%define TEAM_ID         0
%define TEAM_SEQ        4               ; bumped on every change to the team's issues
%define TEAM_NEXT_NUM   8               ; the next issue number, the 12 in ENG-12
%define TEAM_KEY_LEN    12
%define TEAM_KEY        13              ; TEAM_KEY_MAX bytes
%define TEAM_NAME_LEN   18
%define TEAM_NAME       19              ; TEAMNAME_MAX bytes
%define TEAM_LABELS     64              ; LABEL_SLOTS * LABEL_SIZE
%define TEAM_PROJECTS   576             ; PROJECT_SLOTS * PROJ_SIZE, slot 1 first
%define TEAM_SIZE       1216

%define MEM_TEAM        0               ; 0 marks a free slot
%define MEM_USER        4
%define MEM_ROLE        8
%define MEM_SIZE        16

%define ISS_ID          0               ; 0 marks a free slot
%define ISS_TEAM        4
%define ISS_NUMBER      8
%define ISS_ASSIGNEE    12
%define ISS_CREATOR     16
%define ISS_CREATED     20              ; unix seconds
%define ISS_UPDATED     24
%define ISS_LABELS      28              ; u16, bit n = label slot n
%define ISS_STATUS      30
%define ISS_PRIORITY    31
%define ISS_PROJECT     32
%define ISS_TITLE_LEN   33
%define ISS_DESC_LEN    34              ; u16
%define ISS_TITLE       36              ; TITLE_MAX bytes
%define ISS_DESC        156             ; DESC_MAX bytes
%define ISSUE_SIZE      1664

%define CMT_ID          0               ; 0 marks a free slot
%define CMT_ISSUE       4
%define CMT_AUTHOR      8
%define CMT_CREATED     12
%define CMT_LEN         16              ; u16
%define CMT_TEXT        18              ; COMMENT_MAX bytes
%define CMT_EDITED      518             ; u8, 1 once its author changed it
%define CMT_SIZE        520

; Connections keep a session's slot index. A slot with user 0 is free.
; Only the token's SHA-256 is kept.
%define SESS_HASH       0
%define SESS_USER       32
%define SESS_LAST_OP    36              ; highest op number applied for this session
%define SESS_EXPIRES    40              ; unix seconds
%define SESS_SIZE       48
%define SESSION_DAYS    30

%define MS_ID           0               ; 0 marks a free slot
%define MS_TEAM         4
%define MS_FROM         8
%define MS_TO           12              ; 0 for the team's channel
%define MS_CREATED      16
%define MS_LEN          20              ; u16
%define MS_TEXT         22              ; MESSAGE_MAX bytes
%define MS_EDITED       522             ; u8, 1 once its author changed it
%define MS_SIZE         528

; The newest message a member has seen in one of their conversations.
%define SEEN_USER       0               ; 0 marks a free slot
%define SEEN_TEAM       4
%define SEEN_PEER       8               ; 0 for the team's channel
%define SEEN_LAST       12
%define SEEN_SIZE       16

fits USER_NAME, USERNAME_MAX, USER_SALT
fits USER_SALT, 16, USER_HASH
fits USER_HASH, 32, USER_SIZE
fits LABEL_NAME, LABEL_NAME_MAX, LABEL_SIZE
fits PROJ_NAME, PROJECT_NAME_MAX, PROJ_SIZE
fits TEAM_KEY, TEAM_KEY_MAX, TEAM_NAME_LEN
fits TEAM_NAME, TEAMNAME_MAX, TEAM_LABELS
fits TEAM_LABELS, LABEL_SLOTS * LABEL_SIZE, TEAM_PROJECTS
fits TEAM_PROJECTS, PROJECT_SLOTS * PROJ_SIZE, TEAM_SIZE
fits ISS_TITLE, TITLE_MAX, ISS_DESC
fits ISS_DESC, DESC_MAX, ISSUE_SIZE
fits CMT_TEXT, COMMENT_MAX, CMT_EDITED
fits CMT_EDITED, 1, CMT_SIZE
fits SESS_HASH, 32, SESS_USER
fits MS_LEN, 2, MS_TEXT
fits MS_TEXT, MESSAGE_MAX, MS_EDITED
fits MS_EDITED, 1, MS_SIZE
fits SEEN_LAST, 4, SEEN_SIZE

; A team's channel besides #general. Messages in it go to CHANNEL_PEER + slot.
%define CHN_TEAM        0               ; 0 marks a free slot
%define CHN_CREATOR     4
%define CHN_SLOT        8               ; 1 to CHANNEL_SLOTS
%define CHN_NAME_LEN    9
%define CHN_NAME        10              ; CHANNEL_NAME_MAX bytes
%define CHN_SIZE        40
fits CHN_NAME, CHANNEL_NAME_MAX, CHN_SIZE

; An image attached to a message or comment, or on its way to being. The
; PNG itself is a file, see images.asm.
%define IMG_ID          0               ; random, 0 marks a free slot
%define IMG_TEAM        4
%define IMG_OWNER       8               ; who uploaded it
%define IMG_TO          12              ; the conversation's peer, 0 for #general or a comment
%define IMG_PARENT      16              ; the message or comment it's on, once attached
%define IMG_BYTES       20
%define IMG_GOT         24              ; bytes in the file so far
%define IMG_WIDTH       28              ; u16
%define IMG_HEIGHT      30              ; u16
%define IMG_KIND        32              ; u8, IMAGE_ON_*, 0 until attached
%define IMG_SIZE        36
%define IMAGE_ON_MESSAGE 1              ; IMG_KIND
%define IMAGE_ON_COMMENT 2
fits IMG_WIDTH, 2, IMG_HEIGHT
fits IMG_HEIGHT, 2, IMG_KIND
fits IMG_KIND, 1, IMG_SIZE

%define MAX_USERS       1024
%define MAX_TEAMS       512
%define MAX_MEMBERS     8192
%define MAX_ISSUES      16384
%define MAX_COMMENTS    32768
%define MAX_SESSIONS    4096
%define MAX_MESSAGES    32768           ; when full, the oldest message makes room
%define MAX_SEEN        32768
%define MAX_CHANNELS    (MAX_TEAMS * CHANNEL_SLOTS)
%define MAX_IMAGES      4096

%define T_USERS         0
%define T_TEAMS         1
%define T_MEMBERS       2
%define T_ISSUES        3
%define T_COMMENTS      4
%define T_SESSIONS      5
%define T_MESSAGES      6
%define T_SEEN          7
%define T_CHANNELS      8
%define T_IMAGES        9
%define HEADER_TABLES   8               ; the tables whose counts are in the header
%define T_HEADER        0xff

%define DB_MAGIC        0x33445441      ; "ATD3"
; Version 2 gave comments CMT_EDITED in bytes that were always zero before,
; and version 3 added the channels table after the others, and MS_EDITED,
; also in bytes that were always zero. Version 4 added the images table
; after that. Older files load as they are, without the tables they're
; older than, and get saved as version 4.
%define DB_VERSION      4
%define DB_VERSION_MIN  1
%define DB_HEADER       96
%define HEADER_LOGGED   64              ; the part without the private key
%define JOURNAL_MAGIC   0x314a5441      ; "ATJ1"
%define JOURNAL_MAX     (8 * 1024 * 1024)
%define DIRTY_MAX       4096
; Big enough for a whole journal: JOURNAL_MAX plus the largest batch.
%define JBUF_SIZE       (16 * 1024 * 1024)

section .rodata
pub_suffix:         db ".pub", 0
tmp_suffix:         db ".tmp", 0
log_suffix:         db ".log", 0
dot_dir:            db ".", 0
msg_db_bad:         db "todo-server: the database file is unreadable or corrupt, refusing to touch it", 10, 0
msg_db_save:        db "todo-server: can't save the database, stopping so nothing unsaved gets acknowledged", 10, 0
msg_db_path:        db "todo-server: database path is too long", 10, 0

; The tables in file order: address, count variable, row size, capacity.
align 8
db_tables:
    dq users,    n_users,    USER_SIZE,  MAX_USERS
    dq teams,    n_teams,    TEAM_SIZE,  MAX_TEAMS
    dq members,  n_members,  MEM_SIZE,   MAX_MEMBERS
    dq issues,   n_issues,   ISSUE_SIZE, MAX_ISSUES
    dq comments, n_comments, CMT_SIZE,   MAX_COMMENTS
    dq sessions, n_sessions, SESS_SIZE,  MAX_SESSIONS
    dq messages, n_messages, MS_SIZE,    MAX_MESSAGES
    dq seen,     n_seen,     SEEN_SIZE,  MAX_SEEN
    dq channels, n_channels, CHN_SIZE,   MAX_CHANNELS
    dq images,   n_images,   IMG_SIZE,   MAX_IMAGES
TABLE_COUNT equ ($ - db_tables) / 32

section .bss

db_path:            resq 1
tmp_path:           resb 4096
pub_path:           resb 4096
log_path:           resb 4096
dir_path:           resb 4096
journal_fd:         resd 1
journal_size:       resq 1
dirty_count:        resd 1
dirty_overflow:     resb 1
dirty_table:        resb DIRTY_MAX
alignb 4
dirty_slot:         resd DIRTY_MAX

db_header:
db_magic:           resd 1
db_version:         resd 1
db_generation:      resd 1
next_user_id:       resd 1
next_team_id:       resd 1
next_issue_id:      resd 1
next_comment_id:    resd 1
n_users:            resd 1                  ; every count is a high-water mark of used slots
n_teams:            resd 1
n_members:          resd 1
n_issues:           resd 1
n_comments:         resd 1
n_sessions:         resd 1
next_message_id:    resd 1                  ; these three came later, so older files hold zeros here
n_messages:         resd 1
n_seen:             resd 1
                    resb HEADER_LOGGED - 64
server_keys:                                ; private || public, the shape noise_server_respond wants
server_priv:        resb 32                 ; last 32 bytes of the header
server_pub:         resb 32                 ; derived at startup, never written
n_channels:         resd 1                  ; kept in the snapshot after the header's tables
n_images:           resd 1

users:              resb MAX_USERS * USER_SIZE
teams:              resb MAX_TEAMS * TEAM_SIZE
members:            resb MAX_MEMBERS * MEM_SIZE
issues:             resb MAX_ISSUES * ISSUE_SIZE
comments:           resb MAX_COMMENTS * CMT_SIZE
sessions:           resb MAX_SESSIONS * SESS_SIZE
messages:           resb MAX_MESSAGES * MS_SIZE
seen:               resb MAX_SEEN * SEEN_SIZE
channels:           resb MAX_CHANNELS * CHN_SIZE
images:             resb MAX_IMAGES * IMG_SIZE
jbuf:               resb JBUF_SIZE

section .text

; rdi = dst, rsi = db path, rdx = suffix
path_with_suffix:
    push rdx
    call put_cstr
    pop rsi
    call put_cstr
    mov byte [rdi], 0
    ret

; rdi = fd, rsi = buf, rdx = len -> eax = 0 if exactly len bytes were read
read_exact:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
.loop:
    test r13, r13
    jz .ok
    mov eax, SYS_read
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    syscall
    cmp rax, -EINTR
    je .loop
    test rax, rax
    jle .fail
    add r12, rax
    sub r13, rax
    jmp .loop
.ok:
    xor eax, eax
    jmp .done
.fail:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; rdi = bytes, rsi = length -> eax = FNV-1a
fnv1a:
    mov eax, 0x811c9dc5
.byte:
    test rsi, rsi
    jz .done
    movzx ecx, byte [rdi]
    xor eax, ecx
    imul eax, eax, 0x01000193
    inc rdi
    dec rsi
    jmp .byte
.done:
    ret

; -> eax = 1 if every table's count fits its capacity
counts_ok:
    lea rcx, [db_tables]
    mov edx, TABLE_COUNT
.table:
    mov rax, [rcx + 8]
    mov eax, [rax]
    cmp rax, [rcx + 24]
    ja .bad
    add rcx, 32
    dec edx
    jnz .table
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

; rdi = database path. Loads it, or creates a fresh one with a new server key.
db_load:
    push rbx
    push r12
    push r13
    mov [db_path], rdi
    call strlen
    cmp rax, 4000
    jae .path_too_long
    lea rdi, [tmp_path]
    mov rsi, [db_path]
    lea rdx, [tmp_suffix]
    call path_with_suffix
    lea rdi, [pub_path]
    mov rsi, [db_path]
    lea rdx, [pub_suffix]
    call path_with_suffix
    lea rdi, [log_path]
    mov rsi, [db_path]
    lea rdx, [log_suffix]
    call path_with_suffix
    call find_dir
    call image_init

    mov eax, SYS_open
    mov rdi, [db_path]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    syscall
    cmp eax, -ENOENT
    je .fresh
    test eax, eax
    js .bad
    mov ebx, eax
    mov edi, ebx
    lea rsi, [db_header]
    mov edx, DB_HEADER
    call read_exact
    test eax, eax
    jnz .bad
    cmp dword [db_magic], DB_MAGIC
    jne .bad
    mov eax, [db_version]
    cmp eax, DB_VERSION
    ja .bad
    cmp eax, DB_VERSION_MIN
    jb .bad
    lea r12, [db_tables]
    xor r13d, r13d
.table:
    cmp r13d, HEADER_TABLES
    jb .rows
    lea eax, [r13d - HEADER_TABLES + 3]     ; each table after them came a version after the last
    cmp [db_version], eax
    jb .loaded
    mov edi, ebx
    mov rsi, [r12 + 8]
    mov edx, 4
    call read_exact
    test eax, eax
    jnz .bad
.rows:
    call counts_ok
    test eax, eax
    jz .bad
    mov rcx, [r12 + 8]
    mov ecx, [rcx]
    imul rcx, [r12 + 16]
    mov edi, ebx
    mov rsi, [r12]
    mov rdx, rcx
    call read_exact
    test eax, eax
    jnz .bad
    add r12, 32
    inc r13d
    cmp r13d, TABLE_COUNT
    jb .table
.loaded:
    mov eax, SYS_close
    mov edi, ebx
    syscall
    call open_journal
    call replay_journal
    call drop_partial_images
    cmp dword [next_message_id], 0
    jne .compact
    mov dword [next_message_id], 1          ; a database from before messages
    jmp .compact

.fresh:
    mov dword [db_magic], DB_MAGIC
    mov dword [db_version], DB_VERSION
    mov dword [next_user_id], 1
    mov dword [next_team_id], 1
    mov dword [next_issue_id], 1
    mov dword [next_comment_id], 1
    mov dword [next_message_id], 1
    lea rdi, [server_priv]
    mov esi, 32
    call random_bytes
    call open_journal
.compact:
    call db_compact
    lea rdi, [server_pub]
    lea rsi, [server_priv]
    call x25519_public
    pop r13
    pop r12
    pop rbx
    ret
.path_too_long:
    lea rdi, [msg_db_path]
    jmp .die
.bad:
    lea rdi, [msg_db_bad]
.die:
    call print_err
    mov edi, 1
    call exit

; dir_path = the directory holding the database, so renames into it can be synced.
find_dir:
    lea rdi, [dir_path]
    mov rsi, [db_path]
    call put_cstr
    mov byte [rdi], 0
    lea rcx, [dir_path]
.back:
    cmp rdi, rcx
    je .no_slash
    dec rdi
    cmp byte [rdi], '/'
    jne .back
    cmp rdi, rcx
    jne .cut
    inc rdi                                 ; the root directory keeps its slash
.cut:
    mov byte [rdi], 0
    ret
.no_slash:
    lea rdi, [dir_path]
    lea rsi, [dot_dir]
    call put_cstr
    mov byte [rdi], 0
    ret

open_journal:
    mov eax, SYS_open
    lea rdi, [log_path]
    mov esi, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC
    mov edx, 0o600
    syscall
    test eax, eax
    js db_fail
    mov [journal_fd], eax
    ret

; Applies every complete batch in the journal. A torn batch at the end is a
; crash mid-write, never acknowledged, so it's dropped.
replay_journal:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax, SYS_lseek
    mov edi, [journal_fd]
    xor esi, esi
    mov edx, 2                              ; SEEK_END
    syscall
    test rax, rax
    js .corrupt
    cmp rax, JBUF_SIZE
    ja .corrupt
    mov rbx, rax                            ; size
    cmp rbx, 8
    jb .done
    mov eax, SYS_lseek
    mov edi, [journal_fd]
    xor esi, esi
    xor edx, edx
    syscall
    mov edi, [journal_fd]
    lea rsi, [jbuf]
    mov rdx, rbx
    call read_exact
    test eax, eax
    jnz .corrupt
    cmp dword [jbuf], JOURNAL_MAGIC
    jne .done
    mov eax, [db_generation]
    cmp [jbuf + 4], eax
    jne .done                               ; left over from before the last snapshot
    mov r12d, 8                             ; position
.batch:
    mov rax, rbx
    sub rax, r12
    cmp rax, 8
    jb .done
    mov r13d, [jbuf + r12]                  ; length
    sub rax, 8
    cmp rax, r13
    jb .done
    lea rdi, [jbuf + r12 + 4]
    mov rsi, r13
    call fnv1a
    lea rcx, [r12 + r13 + 4]
    cmp eax, [jbuf + rcx]
    jne .done
    lea r14, [jbuf + r12 + 4]               ; record cursor
    lea r15, [r14 + r13]                    ; batch end
.record:
    cmp r14, r15
    jae .next_batch
    movzx eax, byte [r14]
    cmp eax, T_HEADER
    je .header
    cmp eax, TABLE_COUNT
    jae .corrupt
    shl eax, 5
    lea rcx, [db_tables + rax]
    mov rax, r15
    sub rax, r14
    sub rax, 5
    jb .corrupt
    cmp rax, [rcx + 16]
    jb .corrupt
    mov eax, [r14 + 1]                      ; slot
    cmp rax, [rcx + 24]
    jae .corrupt
    ; The header record restores the other counts, but not these.
    cmp byte [r14], HEADER_TABLES
    jb .copy
    mov rdx, [rcx + 8]
    lea edi, [eax + 1]
    cmp [rdx], edi
    jae .copy
    mov [rdx], edi
.copy:
    imul rax, [rcx + 16]
    mov rdi, [rcx]
    add rdi, rax
    lea rsi, [r14 + 5]
    mov rdx, [rcx + 16]
    add r14, rdx
    add r14, 5
    mov rcx, rdx
    rep movsb
    jmp .record
.header:
    mov rax, r15
    sub rax, r14
    cmp rax, HEADER_LOGGED + 1
    jb .corrupt
    lea rsi, [r14 + 1]
    lea rdi, [db_header]
    mov ecx, HEADER_LOGGED
    rep movsb
    add r14, HEADER_LOGGED + 1
    jmp .record
.next_batch:
    lea r12, [r12 + r13 + 8]
    jmp .batch
.done:
    cmp dword [db_magic], DB_MAGIC
    jne .corrupt
    call counts_ok
    test eax, eax
    jz .corrupt
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.corrupt:
    lea rdi, [msg_db_bad]
    call print_err
    mov edi, 1
    call exit

; Folds everything into a new snapshot and starts an empty journal for it.
db_compact:
    call db_save
    mov eax, SYS_ftruncate
    mov edi, [journal_fd]
    xor esi, esi
    syscall
    test eax, eax
    jnz db_fail
    mov dword [jbuf], JOURNAL_MAGIC
    mov eax, [db_generation]
    mov [jbuf + 4], eax
    mov edi, [journal_fd]
    lea rsi, [jbuf]
    mov edx, 8
    call write_all
    test rax, rax
    jnz db_fail
    mov eax, SYS_fdatasync
    mov edi, [journal_fd]
    syscall
    test eax, eax
    jnz db_fail
    mov qword [journal_size], 8
    mov dword [dirty_count], 0
    mov byte [dirty_overflow], 0
    ret

; Writes a snapshot to path.tmp, fsyncs, renames it over the real file and
; syncs the directory so the rename itself is durable.
db_save:
    push rbx
    push r12
    push r13
    inc dword [db_generation]
    mov dword [db_version], DB_VERSION      ; an old file gets saved as the current version
    mov eax, SYS_open
    lea rdi, [tmp_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0o600
    syscall
    test eax, eax
    js db_fail
    mov ebx, eax
    mov edi, ebx
    lea rsi, [db_header]
    mov edx, DB_HEADER
    call write_all
    test rax, rax
    jnz db_fail
    lea r12, [db_tables]
    xor r13d, r13d
.table:
    cmp r13d, HEADER_TABLES
    jb .rows
    mov rsi, [r12 + 8]                      ; its count, which the header has no room for
    mov edi, ebx
    mov edx, 4
    call write_all
    test rax, rax
    jnz db_fail
.rows:
    mov rdx, [r12 + 8]
    mov edx, [rdx]
    imul rdx, [r12 + 16]
    mov rsi, [r12]
    mov edi, ebx
    call write_all
    test rax, rax
    jnz db_fail
    add r12, 32
    inc r13d
    cmp r13d, TABLE_COUNT
    jb .table
    mov eax, SYS_fsync
    mov edi, ebx
    syscall
    test eax, eax
    jnz db_fail
    mov eax, SYS_close
    mov edi, ebx
    syscall
    mov eax, SYS_rename
    lea rdi, [tmp_path]
    mov rsi, [db_path]
    syscall
    test eax, eax
    jnz db_fail
    mov eax, SYS_open
    lea rdi, [dir_path]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    syscall
    test eax, eax
    js db_fail
    mov ebx, eax
    mov eax, SYS_fsync
    mov edi, ebx
    syscall
    test eax, eax
    jnz db_fail
    mov eax, SYS_close
    mov edi, ebx
    syscall
    pop r13
    pop r12
    pop rbx
    ret

; A change must never be acknowledged unless it's on disk, so failing to
; save stops the server.
db_fail:
    lea rdi, [msg_db_save]
    call print_err
    mov edi, 1
    call exit

; Marks a row to be written by the next db_commit. edi = table, rsi = row
db_touch:
    mov eax, edi
    shl eax, 5
    lea rcx, [db_tables + rax]
    mov rax, rsi
    sub rax, [rcx]
    xor edx, edx
    div qword [rcx + 16]
    mov ecx, [dirty_count]
    cmp ecx, DIRTY_MAX
    jae .overflow
    mov [dirty_table + rcx], dil
    mov [dirty_slot + rcx * 4], eax
    inc dword [dirty_count]
    ret
.overflow:
    mov byte [dirty_overflow], 1            ; db_commit takes a snapshot instead
    ret

; Makes every touched row durable.
db_commit:
    push rbx
    push r12
    push r13
    cmp byte [dirty_overflow], 0
    jne .compact
    cmp dword [dirty_count], 0
    je .done
    lea rdi, [jbuf + 4]
    xor ebx, ebx
.record:
    cmp ebx, [dirty_count]
    jae .header
    movzx eax, byte [dirty_table + rbx]
    stosb
    mov ecx, [dirty_slot + rbx * 4]
    mov [rdi], ecx
    add rdi, 4
    shl eax, 5
    lea rdx, [db_tables + rax]
    mov rax, rcx
    imul rax, [rdx + 16]
    mov rsi, [rdx]
    add rsi, rax
    mov rcx, [rdx + 16]
    rep movsb
    inc ebx
    jmp .record
.header:
    mov al, T_HEADER
    stosb
    lea rsi, [db_header]
    mov ecx, HEADER_LOGGED
    rep movsb
    mov r12, rdi
    lea rax, [jbuf + 4]
    sub r12, rax                            ; records length
    mov [jbuf], r12d
    lea rdi, [jbuf + 4]
    mov rsi, r12
    call fnv1a
    mov [jbuf + r12 + 4], eax
    lea r13, [r12 + 8]
    mov edi, [journal_fd]
    lea rsi, [jbuf]
    mov rdx, r13
    call write_all
    test rax, rax
    jnz db_fail
    mov eax, SYS_fdatasync
    mov edi, [journal_fd]
    syscall
    test eax, eax
    jnz db_fail
    mov dword [dirty_count], 0
    add [journal_size], r13
    cmp qword [journal_size], JOURNAL_MAX
    jb .done
.compact:
    call db_compact
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Writes the public key as hex to <db>.pub so clients can be pointed at it.
write_pub_file:
    push rbx
    sub rsp, 80
    mov rdi, rsp
    lea rsi, [server_pub]
    mov edx, 32
    call put_hex
    mov byte [rdi], 10
    mov eax, SYS_open
    lea rdi, [pub_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0o644
    syscall
    test eax, eax
    js .done
    mov ebx, eax
    mov edi, ebx
    mov rsi, rsp
    mov edx, 65
    call write_all
    mov eax, SYS_close
    mov edi, ebx
    syscall
.done:
    add rsp, 80
    pop rbx
    ret

; Finds a free slot, growing the table if there's none. Every table but
; sessions starts with a field that's 0 when free.
; edi = table -> rax = the zeroed row, or 0 if the table is full
alloc_row:
    push rbx
    mov eax, edi
    shl eax, 5
    lea rbx, [db_tables + rax]
    mov rax, [rbx]
    mov rcx, [rbx + 8]
    mov ecx, [rcx]
    mov rdx, [rbx + 16]
.scan:
    test ecx, ecx
    jz .grow
    cmp dword [rax], 0
    je .found
    add rax, rdx
    dec ecx
    jmp .scan
.grow:
    mov rcx, [rbx + 8]
    mov ecx, [rcx]
    cmp rcx, [rbx + 24]
    jae .full
    mov rcx, [rbx + 8]
    inc dword [rcx]
.found:
    push rax
    mov rdi, rax
    mov rsi, rdx
    call wipe
    pop rax
    pop rbx
    ret
.full:
    xor eax, eax
    pop rbx
    ret

; --- lookups. They return a row pointer, or 0. ---

; rsi = name, edx = length
find_user_by_name:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rsi
    mov r13d, edx
    lea rbx, [users]
    mov r14d, [n_users]
.loop:
    test r14d, r14d
    jz .none
    movzx eax, byte [rbx + USER_NAME_LEN]
    cmp eax, r13d
    jne .next
    lea rdi, [rbx + USER_NAME]
    mov rsi, r12
    mov edx, r13d
    call mem_eq
    test eax, eax
    jnz .found
.next:
    add rbx, USER_SIZE
    dec r14d
    jmp .loop
.none:
    xor ebx, ebx
.found:
    mov rax, rbx
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Free slots have id 0, so 0 never matches.
%macro FIND_BY_ID 4             ; name, table, count, row size
%1:
    lea rax, [%2]
    mov ecx, [%3]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax], edi
    je .done
    add rax, %4
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret
%endmacro

; edi = id
FIND_BY_ID find_user, users, n_users, USER_SIZE
FIND_BY_ID find_team, teams, n_teams, TEAM_SIZE
FIND_BY_ID find_issue, issues, n_issues, ISSUE_SIZE

; edi = team, esi = user
find_member:
    lea rax, [members]
    mov ecx, [n_members]
    test edi, edi
    jz .none
.loop:
    test ecx, ecx
    jz .none
    cmp [rax + MEM_TEAM], edi
    jne .next
    cmp [rax + MEM_USER], esi
    je .done
.next:
    add rax, MEM_SIZE
    dec ecx
    jmp .loop
.none:
    xor eax, eax
.done:
    ret

; Counts rows whose u32 at an offset equals a value, which is never 0.
; edi = table, esi = offset, edx = value -> eax = count
count_where:
    push rbx
    shl edi, 5
    lea rbx, [db_tables + rdi]
    mov rdi, [rbx]
    mov rcx, [rbx + 8]
    mov ecx, [rcx]
    mov r8, [rbx + 16]
    xor eax, eax
    test edx, edx
    jz .done
.row:
    test ecx, ecx
    jz .done
    cmp [rdi + rsi], edx
    jne .next
    inc eax
.next:
    add rdi, r8
    dec ecx
    jmp .row
.done:
    pop rbx
    ret

; Frees a row: wiped, so it reads as a free slot, and touched for the journal.
; edi = table, rsi = row
free_row:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12, rsi
    call drop_attached_image
    mov edi, ebx
    shl edi, 5
    mov rsi, [db_tables + rdi + 16]
    mov rdi, r12
    call wipe
    mov edi, ebx
    mov rsi, r12
    call db_touch
    add rsp, 8
    pop r12
    pop rbx
    ret
