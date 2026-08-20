#!/usr/bin/env bash
# Assert the record stand_down_extensions/restore_extensions keep in
# $CONF_DIR/modes/solid/disabled-extensions round-trips correctly across more
# than one run — not just what the announcement text says about it.
#
# tools/check-glass-modes.sh drives install.sh --dry-run, which is the only
# safe way to exercise install.sh's own flag parsing, but every record read,
# write and delete in these two functions is gated behind DRY_RUN — a dry run
# can only ever prove the wording. This script calls the functions directly
# instead, with DRY_RUN=0, against a stub gnome-extensions and a scratch
# $HOME, so the actual file on disk is what gets checked. It never runs
# install.sh itself and never touches the developer's real GNOME session:
# gsettings and dconf talk to the live session bus no matter what $HOME says,
# so a real (non-dry) install.sh run is never safe here — only the two
# extension functions, with gnome-extensions itself stubbed out, are.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# lib/steps.sh derives CONF_DIR and EXT_DIR from $HOME with a plain
# assignment, not a conditional default, so pointing them at the scratch
# directory means pointing $HOME there before sourcing it — setting CONF_DIR
# or EXT_DIR directly would just be overwritten the moment it is sourced.
export HOME="$scratch"
mkdir -p "$HOME/.local/share/gnome-shell/extensions"

# A stub gnome-extensions, driven by a plain file rather than a live shell, so
# "enabled" is whatever this script says it is and "disable"/"enable" are
# just logged rather than touching anything real.
mkdir -p "$scratch/fakebin"
FAKE_ENABLED="$scratch/fake-enabled"
FAKE_LOG="$scratch/fake-log"
: > "$FAKE_ENABLED"
: > "$FAKE_LOG"
cat > "$scratch/fakebin/gnome-extensions" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    list)
        cat "$FAKE_ENABLED" 2>/dev/null
        ;;
    disable)
        echo "disable:$2" >> "$FAKE_LOG"
        grep -vxF "$2" "$FAKE_ENABLED" > "$FAKE_ENABLED.tmp" 2>/dev/null || : > "$FAKE_ENABLED.tmp"
        mv "$FAKE_ENABLED.tmp" "$FAKE_ENABLED"
        ;;
    enable)
        echo "enable:$2" >> "$FAKE_LOG"
        printf '%s\n' "$2" >> "$FAKE_ENABLED"
        ;;
    *)
        exit 1
        ;;
esac
STUB
chmod +x "$scratch/fakebin/gnome-extensions"
export PATH="$scratch/fakebin:$PATH" FAKE_ENABLED FAKE_LOG

# lib/*.sh are definitions only — nothing runs at source time — so sourcing
# them stand-alone, the same way install.sh sources all six, is safe.
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/steps.sh
source "$ROOT/lib/steps.sh"
# shellcheck source=lib/steps-extensions.sh
source "$ROOT/lib/steps-extensions.sh"

record="$CONF_DIR/modes/solid/disabled-extensions"
DRY_RUN=0

own=(user-theme@gnome-shell-extensions.gcampax.github.com openbar@neuromorph "$BMS_UUID")
foreign="app-hider@lynith.dev"            # the user's own — never ours to touch
substring_trap="openbar@neuromorph-nightly"  # a superstring of an owned UUID

# "installed" for every UUID restore_extensions will be asked about, so the
# "no longer installed" skip never masks what is actually under test.
for u in "${own[@]}" custom-osd@neuromorph; do mkdir -p "$EXT_DIR/$u"; done

# --- first entry: the record names exactly what was owned and enabled ---
printf '%s\n' "${own[@]}" "$foreign" > "$FAKE_ENABLED"
: > "$FAKE_LOG"
stand_down_extensions >/dev/null
got="$(sort "$record" 2>/dev/null)"
want="$(printf '%s\n' "${own[@]}" | sort)"
[ "$got" = "$want" ] || failures+=(
    "first entry: record should name exactly ${own[*]}, got: $(tr '\n' ' ' <<< "$got")")
grep -qxF "disable:$foreign" "$FAKE_LOG" && failures+=(
    "first entry: $foreign is not ours, it must never reach gnome-extensions disable")
for u in "${own[@]}"; do
    grep -qxF "disable:$u" "$FAKE_LOG" || failures+=("first entry: $u should have been disabled, was not")
done

# --- second entry: everything of ours is already off — the record from the
# first entry must survive completely untouched, not be truncated. ---
before="$(cat "$record")"
: > "$FAKE_LOG"
out="$(stand_down_extensions)"
after="$(cat "$record" 2>/dev/null)"
[ "$before" = "$after" ] || failures+=(
    "second entry with ours already off should leave the record untouched, it changed")
case "$out" in
    *"none of this project's extensions are enabled"*) ;;
    *) failures+=("second entry should report nothing of ours enabled, got: $out") ;;
esac
[ -s "$FAKE_LOG" ] && failures+=("second entry disabled something it should not have: $(cat "$FAKE_LOG")")

# --- union: one already-recorded UUID comes back on by hand, one new UUID
# goes off — the record must end up holding both, not replace the old with
# the new. ---
printf '%s\n' "${own[0]}" custom-osd@neuromorph >> "$FAKE_ENABLED"
: > "$FAKE_LOG"
stand_down_extensions >/dev/null
got="$(sort "$record")"
want="$(printf '%s\n' "${own[@]}" custom-osd@neuromorph | sort -u)"
[ "$got" = "$want" ] || failures+=(
    "union entry: record should hold the union of what it already named and what just went off, got: $(tr '\n' ' ' <<< "$got")")

# --- substring safety: an enabled UUID that merely contains an owned one
# must not be treated as enabled, and must not disturb the record. ---
printf '%s\n' "$substring_trap" > "$FAKE_ENABLED"
before="$(cat "$record")"
: > "$FAKE_LOG"
stand_down_extensions >/dev/null
[ -s "$FAKE_LOG" ] && failures+=(
    "substring UUID $substring_trap reached gnome-extensions disable — it is not openbar@neuromorph")
after="$(cat "$record")"
[ "$before" = "$after" ] || failures+=("the substring case should leave the record untouched, it changed")

# --- leaving solid: exactly what the record names comes back on, then the
# record itself goes. ---
printf '%s\n' "${own[@]}" custom-osd@neuromorph > "$record"
: > "$FAKE_LOG"
: > "$FAKE_ENABLED"
restore_extensions >/dev/null
for u in "${own[@]}" custom-osd@neuromorph; do
    grep -qxF "enable:$u" "$FAKE_LOG" || failures+=("restore should have enabled $u, did not")
done
[ -e "$record" ] && failures+=("restore should delete the record once everything is back on, it is still there")

# --- an empty or whitespace-only record is not "nothing was ever switched
# off" — it must be left alone, not silently deleted. ---
printf '   \n\n' > "$record"
out="$(restore_extensions 2>&1)"
[ -e "$record" ] || failures+=("an empty record should be left alone, not deleted")
case "$out" in
    *"exists but names nothing"*) ;;
    *) failures+=("an empty record should be reported, not silently swallowed — got: $out") ;;
esac
rm -f "$record"

# --- no record at all: restore_extensions must return immediately and
# print nothing, since it runs on every non-solid run. ---
out="$(restore_extensions 2>&1)"
[ -z "$out" ] || failures+=("restore_extensions with no record should print nothing, got: $out")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'solid-extensions check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'solid-extensions check passed — first entry, repeat entry, union, substring safety, restore, an empty record and no record all covered\n'
