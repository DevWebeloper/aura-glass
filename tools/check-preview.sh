#!/usr/bin/env bash
# Assert that bin/aura-glass-preview leaves the desktop showing a candidate
# without ever leaving a $CONF_DIR memo different from what it found.
#
# Unlike tools/check-radius-preset.sh this cannot run in an isolated tmpdir:
# aura-glass-preview calls the real install_css / apply_radius_dconf /
# apply_app_blur / apply_popup_blur / apply_blur_pipelines, which write real
# CSS under $CONF_DIR, real dconf keys under
# /org/gnome/shell/extensions/blur-my-shell, and — through
# ~/.local/bin/aura-glass-apply — the real installed theme and
# ~/.config/gtk-4.0. So this only runs on a machine with aura-glass actually
# installed, and it is the machine's own live state it checks against: begin,
# then a set that changes nothing, must leave every sheet byte-identical and
# every memo untouched; a set that changes something must show up on disk
# where install_css puts it and still not touch a memo — not even to write one
# and put it back, which is what step 3 is about; and revert must put
# everything — sheets, the blur-my-shell dconf subtree, the memos — back
# exactly where begin found it.
#
# Skips itself where there is nothing installed to preview against, the same
# way tools/check-gui-flags.py skips where PyGObject is absent.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/bin/aura-glass-preview"
CONF_DIR="$HOME/.config/aura-glass"

if [ ! -r "$CONF_DIR/repo-path" ]; then
    echo "check-preview: nothing installed at $CONF_DIR — skipping"
    exit 0
fi
if [ -e "$CONF_DIR/preview-active" ]; then
    echo "check-preview: a preview is already active — skipping rather than clobbering it"
    exit 0
fi
if ! command -v dconf >/dev/null 2>&1; then
    echo "check-preview: no dconf on this machine — skipping"
    exit 0
fi

MEMOS="app-tint-color shell-tint-color app-transparency radius-preset radius-custom blur-strength blur-brightness popup-opacity popup-blur window-blur app-blur-scope app-blur-allow app-blur-block"

hash_sheets() {
    # shellcheck disable=SC2012
    { for f in "$CONF_DIR"/shell-*.css "$CONF_DIR"/gtk4-*.css "$CONF_DIR/gtk3-tweaks.css"; do
          [ -f "$f" ] && md5sum "$f"
      done; } | sort | md5sum
}

memo() { cat "$CONF_DIR/$1" 2>/dev/null || printf '(absent)'; }

# Change times, to nanosecond resolution. Content alone cannot tell "never
# written" from "written and restored" — a restore puts the same bytes back —
# but a write moves ctime and nothing puts that back, so this is what separates
# the two. See step 3.
memo_ctimes() {
    local name
    for name in $MEMOS; do
        printf '%s=%s\n' "$name" \
            "$(stat -c '%z' "$CONF_DIR/$name" 2>/dev/null || printf 'absent')"
    done
}

memo_snapshot() {
    local name
    for name in $MEMOS; do printf '%s=%s\n' "$name" "$(memo "$name")"; done
}

failures=0
fail() { printf '  FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

BASELINE_HASH="$(hash_sheets)"
BASELINE_MEMOS="$(memo_snapshot)"
BASELINE_RADIUS_DCONF="$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/corner-radius 2>/dev/null || true)"

app_tint="$(memo app-tint-color)"; [ "$app_tint" = "(absent)" ] && app_tint="#000000"
shell_tint="$(memo shell-tint-color)"; [ "$shell_tint" = "(absent)" ] && shell_tint="#000000"
transparency="$(memo app-transparency)"; [ "$transparency" = "(absent)" ] && transparency="0"
radius_preset="$(memo radius-preset)"; [ "$radius_preset" = "(absent)" ] && radius_preset="default"
blur_strength="$(memo blur-strength)"; [ "$blur_strength" = "(absent)" ] && blur_strength="100"
blur_brightness="$(memo blur-brightness)"; [ "$blur_brightness" = "(absent)" ] && blur_brightness="100"
popup_opacity="$(memo popup-opacity)"; [ "$popup_opacity" = "(absent)" ] && popup_opacity="main"
popup_blur="$(memo popup-blur)"; [ "$popup_blur" = "(absent)" ] && popup_blur="1"
window_blur="$(memo window-blur)"; [ "$window_blur" = "(absent)" ] && window_blur="1"
scope="$(memo app-blur-scope)"; [ "$scope" = "(absent)" ] && scope="gtk"
[ "$window_blur" = 1 ] || scope="gtk"   # aura-glass-preview's --scope is meaningless with --window-blur 0

cleanup() { "$SCRIPT" revert >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$SCRIPT" begin

echo "1) a no-op set changes nothing on disk"
"$SCRIPT" set --app-tint "$app_tint" --shell-tint "$shell_tint" \
    --transparency "$transparency" --radius-preset "$radius_preset" \
    --blur-strength "$blur_strength" --blur-brightness "$blur_brightness" \
    --popup-opacity "$popup_opacity" \
    --popup-blur "$popup_blur" \
    --window-blur "$window_blur" --scope "$scope" >/dev/null
[ "$(hash_sheets)" = "$BASELINE_HASH" ] \
    || fail "a no-op set changed the installed sheets"
[ "$(memo_snapshot)" = "$BASELINE_MEMOS" ] \
    || fail "a no-op set changed a \$CONF_DIR memo"

echo "2) a real candidate reaches the desktop"
other_radius="rounded"; [ "$radius_preset" = "rounded" ] && other_radius="flat"
"$SCRIPT" set --app-tint "$app_tint" --shell-tint "$shell_tint" \
    --transparency "$transparency" --radius-preset "$other_radius" \
    --blur-strength "$blur_strength" --blur-brightness "$blur_brightness" \
    --popup-opacity "$popup_opacity" \
    --popup-blur "$popup_blur" \
    --window-blur "$window_blur" --scope "$scope" >/dev/null
got="$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/corner-radius 2>/dev/null || true)"
[ -n "$got" ] && [ "$got" != "$BASELINE_RADIUS_DCONF" ] \
    || fail "switching the radius preset did not move the blur-my-shell corner-radius key"
[ "$(memo_snapshot)" = "$BASELINE_MEMOS" ] \
    || fail "a set that changed the desktop still left a \$CONF_DIR memo touched"

echo "3) a set writes no memo at all, not even one it puts back"
# The property this script used to check was the weaker "set writes the memos
# and then restores them". That restore was only safe while nothing else was
# writing the same files, and install.sh --settings-only is exactly something
# else writing them: an Apply pressed while a tick was still in flight had its
# memo put back a moment later, and the settings window re-read the old value —
# so every preset click appeared to snap back to whatever was already
# installed. set now exports PREVIEW_MODE=1 and writes no memo at all, which is
# what this asserts: same bytes is not enough, the files must not have been
# written.
CTIMES_BEFORE="$(memo_ctimes)"
"$SCRIPT" set --app-tint "$app_tint" --shell-tint "$shell_tint" \
    --transparency "$transparency" --radius-preset "$other_radius" \
    --blur-strength "$blur_strength" --blur-brightness "$blur_brightness" \
    --popup-opacity "$popup_opacity" \
    --popup-blur "$popup_blur" \
    --window-blur "$window_blur" --scope "$scope" >/dev/null
[ "$(memo_ctimes)" = "$CTIMES_BEFORE" ] \
    || fail "a set wrote a \$CONF_DIR memo and restored it — PREVIEW_MODE did not reach every apply_* function"

echo "4) apps changes only the per-app blur dconf keys, and writes no memo"
# apps is set's per-app-blur-only sibling — the Per-app blur page's fast
# path for a switch flipped, with no install_css and no aura-glass-apply.
# Round-tripped from the memos themselves rather than a candidate value:
# apps is explicit-only (it never falls back to a memo the way a real
# install.sh run does), so what is already on disk is the one input that is
# guaranteed a no-op here.
CTIMES_BEFORE="$(memo_ctimes)"
SHEETS_BEFORE="$(hash_sheets)"
allow_now="$(tr '\n' ',' < "$CONF_DIR/app-blur-allow" 2>/dev/null | sed 's/,$//')"
block_now="$(tr '\n' ',' < "$CONF_DIR/app-blur-block" 2>/dev/null | sed 's/,$//')"
"$SCRIPT" apps --allow "$allow_now" --block "$block_now" \
    --window-blur "$window_blur" --scope "$scope" >/dev/null
[ "$(hash_sheets)" = "$SHEETS_BEFORE" ] \
    || fail "apps touched the installed CSS sheets"
[ "$(memo_snapshot)" = "$BASELINE_MEMOS" ] \
    || fail "apps changed a \$CONF_DIR memo"
[ "$(memo_ctimes)" = "$CTIMES_BEFORE" ] \
    || fail "apps wrote a \$CONF_DIR memo and restored it — PREVIEW_MODE did not reach apply_app_blur"
got_allow="$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/whitelist 2>/dev/null || true)"
[ -n "$got_allow" ] \
    || fail "apps left the whitelist key empty — the settings window's own class is always pinned onto it"

echo "5) revert restores every sheet, every memo and the dconf subtree byte-for-byte"
"$SCRIPT" revert
[ "$(hash_sheets)" = "$BASELINE_HASH" ] \
    || fail "revert did not restore the installed sheets byte-for-byte"
[ "$(memo_snapshot)" = "$BASELINE_MEMOS" ] \
    || fail "revert left a \$CONF_DIR memo different from what begin found"
got="$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/corner-radius 2>/dev/null || true)"
[ "$got" = "$BASELINE_RADIUS_DCONF" ] \
    || fail "revert did not restore the blur-my-shell corner-radius key"
[ -e "$CONF_DIR/preview-active" ] && fail "revert left the preview-active marker behind"
[ -d "$CONF_DIR/preview-backup" ] && fail "revert left preview-backup behind"

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures problem(s)"
    exit 1
fi
echo "preview check passed"
