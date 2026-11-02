# Contributing

Each binary is one translation unit, so a slip anywhere shows up everywhere. These rules keep the tree in the shape it's in. `make lint` enforces the mechanical ones, and CI runs the build, the tests and the lint on every pull request.

## Before you push

```
make && make test && make lint
```

Warnings are errors. `make lint` fails on a function over 150 lines, a file over 1500 lines, or a function with no comment above it. What was already over the line when the check arrived is listed in `tests/lint-baseline`. Shrink that list when you touch something on it. Never add to it.

## Functions

Every function has a one-line comment above it naming its registers in and out, in the style already used:

```
; rdi = message, rsi = length -> eax = 1 if valid
```

The convention is at the top of `src/common/macros.inc`: arguments in rdi, rsi, rdx, rcx, r8, r9, results in rax, and rbx, rbp, r12-r15 preserved. A function that preserves more says so. One with no arguments still gets a line saying what it does.

## Rows and limits

Limits live in `src/common/config.inc` and nowhere else. Row offsets are typed by hand, so every row layout ends with `fits` lines that fail the build when a field would run into the next one. A new row or field gets its `fits` line in the same commit, and a change that drops one doesn't pass review.

## Protocol

- Message types, op kinds, event kinds and field numbers are appended, never renumbered or reused.
- A new field lands in three places in the same commit: the layout comment in `config.inc`, the writer, and the reader.
- A change to a row that goes on disk bumps `DB_VERSION` in `src/server/db.asm`. The loader refuses a file with another version rather than guessing at it. The exceptions are a new field in bytes that were always zero and a new table after the others, where the previous version still reads correctly as it is. Then the version still goes up, and the loader takes the old ones and saves the new one.

## Crypto and Noise

`src/common/crypto/` and `src/common/noise.asm` are frozen. A change there needs a published test vector in `tests/crypto_test.asm` or a fuzz run against another implementation, and nothing unrelated goes in the same pull request.

## README

The README's Protocol and Layout sections are the design doc. A change to a message, or a move of code between files, updates them in the same commit.

## Tests

A bug fix adds the case that would have caught it. If no test binary covers that layer yet, the fix is where that binary gets created, following `tests/crypto_test.asm`.

## Branches and commits

Short-lived branches, squash-merged into `main`. A commit message is one line in the style of the log, like `feat: drag board cards between columns to change their status`, with no body. Keep tool checkpoints and other workflow leftovers out of the history.

## Review checklist

- The stack is balanced on every exit path.
- rbx, rbp and r12-r15 are restored on every exit path.
- Every run of `rd_` calls ends in an `rd_ok` check.
- Limits come from `config.inc`, not literals.
- New strings use the `text` macro.
- Every new function has its comment and stays under 150 lines.
- A new or changed row has its `fits` lines.
