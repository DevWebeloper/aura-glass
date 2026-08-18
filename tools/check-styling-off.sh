#!/usr/bin/env bash
# Assert bin/aura-glass-apply splices when the theme is up and stands it down
# when the marker is there — against a fixture HOME, never the real desktop.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
conf="$fixture/.config/aura-glass"
mkdir -p "$conf/backups" "$fixture/.config/gtk-4.0" "$fixture/.config/gtk-3.0" \
         "$fixture/.themes/Tahoe-Dark/gnome-shell"

shell_css="$fixture/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css"
gtk4_css="$fixture/.config/gtk-4.0/gtk.css"

printf 'stage { box-shadow: 0 2px 4px rgba(0,0,0,0.5); }\n' > "$shell_css"
cp "$shell_css" "$conf/backups/gnome-shell.css.orig"
printf '/* theme */\nwindow { background: black; }\n' > "$gtk4_css"
cp "$gtk4_css" "$conf/backups/gtk4-gtk.css.orig"
printf 'stage { color: white; }\n' > "$conf/shell-00-flat.css"
printf 'window { color: white; }\n' > "$conf/gtk4-00-flat.css"
printf '* { outline: none; }\n' > "$conf/gtk3-tweaks.css"

apply_it() { HOME="$fixture" bash "$ROOT/bin/aura-glass-apply" >/dev/null 2>&1; }

apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    || failures+=("with no marker the shell sheet should carry the block")
grep -q 'aura-glass BEGIN' "$gtk4_css" \
    || failures+=("with no marker the gtk4 sheet should carry the block")

: > "$conf/styling-off"
apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    && failures+=("with the marker the shell sheet should have no block")
grep -q 'box-shadow: 0 2px 4px' "$shell_css" \
    || failures+=("the shell sheet should be the pristine backup again, shadows and all")
grep -q 'aura-glass BEGIN' "$gtk4_css" \
    && failures+=("with the marker the gtk4 sheet should have no block")

# Twice is the same as once.
before="$(cat "$shell_css")"
apply_it
[ "$before" = "$(cat "$shell_css")" ] \
    || failures+=("standing down twice should change nothing the second time")

# And back again.
rm -f "$conf/styling-off"
apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    || failures+=("removing the marker should put the block back")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'styling-off check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'styling-off check passed — splice, stand down, idempotent, and back\n'
