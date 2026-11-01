#!/bin/bash
# Flags the ways this assembly tends to rot: a function over 150 lines, a file
# over 1500 lines, or a function with no comment above it. Whatever was already
# over the line when this arrived is listed in lint-baseline. A new hit fails,
# and so does a baseline line that no longer matches, so the list only shrinks.
set -euo pipefail
cd "$(dirname "$0")/.."

found=$(find src tests -name '*.asm' | sort | xargs awk '
function flush() {
    if (fn != "" && last - fn_start + 1 > 150) print "long " file " " fn
    fn = ""
}
function end_file() {
    flush()
    if (last > 1500) print "bigfile " file
}
FNR == 1 { if (NR > 1) end_file(); file = FILENAME; sec = ".text"; prev = "" }
/^[ \t]*section[ \t]+\./ { flush(); match($0, /\.[a-z]+/); sec = substr($0, RSTART, RLENGTH) }
/^[A-Za-z_][A-Za-z0-9_]*:/ && sec == ".text" {
    flush()
    fn = $1; sub(/:.*/, "", fn); fn_start = FNR
    if (fn != "_start" && prev !~ /^[ \t]*;/ && prev !~ /^[A-Za-z_][A-Za-z0-9_]*:/) print "nocomment " file " " fn
}
/[^ \t]/ { prev = $0 }
{ last = FNR }
END { end_file() }
' | sort -u)

baseline=$(sed '/^#/d; /^$/d' tests/lint-baseline | sort -u)
new=$(comm -13 <(printf '%s\n' "$baseline" | sed '/^$/d') <(printf '%s\n' "$found" | sed '/^$/d'))
stale=$(comm -23 <(printf '%s\n' "$baseline" | sed '/^$/d') <(printf '%s\n' "$found" | sed '/^$/d'))

status=0
if [ -n "$new" ]; then
    printf 'lint: split these up or add the comment\n%s\n' "$new"
    status=1
fi
if [ -n "$stale" ]; then
    printf 'lint: no longer true, remove from tests/lint-baseline\n%s\n' "$stale"
    status=1
fi
exit $status
