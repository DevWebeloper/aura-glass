#!/usr/bin/env bash
# Assert the installer steps recover from an interrupted earlier run.
#
# Wiggly is moved aside while it is fetched again, and a run killed in that
# window left only the aside copy and never restored it. And the cursor
# settings.ini edit dropped its key when the file had no [Settings] header,
# and turned a symlinked file into a regular one. Run in a throwaway HOME.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
fail=0
check() { if ! "$@"; then echo "FAIL: $*"; fail=1; fi; }

# shellcheck source=/dev/null
. "$repo/lib/common.sh"
# shellcheck source=/dev/null
. "$repo/lib/steps-dconf.sh"
# shellcheck source=/dev/null
. "$repo/lib/steps-extensions.sh"

# Wiggly: only the aside copy exists, so it is put back.
EXT_DIR="$tmp/ext"; REPO_ROOT="$repo"; DRY_RUN=1
mkdir -p "$EXT_DIR/wiggly@mojarch.aura-glass-old"
echo marker > "$EXT_DIR/wiggly@mojarch.aura-glass-old/extension.js"
patch_wiggly_extension >/dev/null 2>&1 || true
check test -f "$EXT_DIR/wiggly@mojarch/extension.js"
check test ! -e "$EXT_DIR/wiggly@mojarch.aura-glass-old"

BMS_UUID="${BMS_UUID:-blur-my-shell@aunetx}"
# Blur My Shell: a run cut off mid-install left only the aside copy, so the
# next run puts it back before anything else (the EGO path is stubbed out).
mkdir -p "$EXT_DIR/.$BMS_UUID.aura-glass-old"
echo marker > "$EXT_DIR/.$BMS_UUID.aura-glass-old/extension.js"
(
    DRY_RUN=0 WANT_BMS_GIT=0 CONF_DIR="$tmp/conf"
    install_ext_ego() { :; }
    install_bms >/dev/null 2>&1 || true
)
check test -f "$EXT_DIR/$BMS_UUID/extension.js"
check test ! -e "$EXT_DIR/.$BMS_UUID.aura-glass-old"

# A header added to a file whose last line has no newline goes on its own line.
printf '# comment' > "$tmp/nonl.ini"
set_gtk_ini_key "$tmp/nonl.ini" gtk-cursor-theme-name Adwaita
check grep -qx '\[Settings\]' "$tmp/nonl.ini"
check grep -qx 'gtk-cursor-theme-name=Adwaita' "$tmp/nonl.ini"

# settings.ini with no [Settings] header gets one, and keeps the key.
ini="$tmp/a.ini"
printf '# comment\n' > "$ini"
set_gtk_ini_key "$ini" gtk-cursor-theme-name Adwaita
check grep -qx 'gtk-cursor-theme-name=Adwaita' "$ini"
check grep -qx '\[Settings\]' "$ini"
set_gtk_ini_key "$ini" gtk-cursor-theme-name Other
check test "$(grep -c '^gtk-cursor-theme-name=' "$ini")" = 1
check grep -qx 'gtk-cursor-theme-name=Other' "$ini"

# A symlinked settings.ini stays a symlink and the target is edited.
printf '[Settings]\ngtk-cursor-theme-size=24\n' > "$tmp/real.ini"
ln -s "$tmp/real.ini" "$tmp/link.ini"
set_gtk_ini_key "$tmp/link.ini" gtk-cursor-theme-size 32
check test -L "$tmp/link.ini"
check grep -qx 'gtk-cursor-theme-size=32' "$tmp/real.ini"

[ "$fail" = 0 ] && echo "installer recovery checks passed"
exit "$fail"
