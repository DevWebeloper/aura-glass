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
gtk4_dark_css="$fixture/.config/gtk-4.0/gtk-dark.css"
gtk3_css="$fixture/.config/gtk-3.0/gtk.css"

# gnome-shell.css and gtk.css: an ordinary first run, with the .orig backup
# install_theme would have taken — stand_down's restore branch.
printf 'stage { box-shadow: 0 2px 4px rgba(0,0,0,0.5); }\n' > "$shell_css"
cp "$shell_css" "$conf/backups/gnome-shell.css.orig"
printf '/* theme */\nwindow { background: black; }\n' > "$gtk4_css"
cp "$gtk4_css" "$conf/backups/gtk4-gtk.css.orig"

# gtk-dark.css: the Tahoe installer made this file where none existed before,
# so backup_once recorded an .absent marker rather than an .orig — stand_down's
# move-aside branch, which has to take the file out of GTK's way without
# throwing it away, because coming back out of solid mode has to bring it back.
printf '/* theme dark */\nwindow { background: black; }\n' > "$gtk4_dark_css"
: > "$conf/backups/gtk4-gtk-dark.css.absent"

# gtk-3.0/gtk.css: no backup record of either kind, and a line of the user's
# own already sitting in it — stand_down's third branch, reached when
# backups/ has neither an .orig nor an .absent for this target. Standing down
# still has to take our block back out; it strips it and leaves the user's
# rule standing, same as it would leave any of the theme's own content alone.
printf '.user-own-rule { color: red; }\n' > "$gtk3_css"

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
[ -e "$gtk4_dark_css" ] \
    && failures+=("gtk-dark.css has only an .absent marker — standing down should move it aside, not leave it behind")
[ -f "$conf/backups/gtk4-gtk-dark.css.stood-down" ] \
    || failures+=("standing down should leave the moved-aside gtk-dark.css in backups/ for coming back")
grep -q 'aura-glass BEGIN' "$gtk3_css" \
    && failures+=("with the marker the gtk3 sheet should have no block")
grep -q 'user-own-rule' "$gtk3_css" \
    || failures+=("gtk3.css has no backup record at all — standing down should strip the block but leave the user's own rule")

# Twice is the same as once, for every target — including the one that no
# longer exists, which has to stay gone rather than reappear.
before_shell="$(cat "$shell_css")"
before_gtk4="$(cat "$gtk4_css")"
before_gtk3="$(cat "$gtk3_css")"
apply_it
[ "$before_shell" = "$(cat "$shell_css")" ] \
    || failures+=("standing down twice should change nothing the second time (shell)")
[ "$before_gtk4" = "$(cat "$gtk4_css")" ] \
    || failures+=("standing down twice should change nothing the second time (gtk4)")
[ "$before_gtk3" = "$(cat "$gtk3_css")" ] \
    || failures+=("standing down twice should change nothing the second time (gtk3)")
[ -e "$gtk4_dark_css" ] \
    && failures+=("standing down twice should leave the moved-aside gtk-dark.css gone from where GTK reads it")

# And back again — every target the stand-down touched, not just the shell
# sheet, because the .stood-down move and the revive that undoes it are
# exactly what a shell-only assertion here would never catch.
rm -f "$conf/styling-off"
apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    || failures+=("removing the marker should put the block back (shell)")
grep -q 'aura-glass BEGIN' "$gtk4_css" \
    || failures+=("removing the marker should put the block back (gtk4)")
if [ -f "$gtk4_dark_css" ]; then
    grep -q 'aura-glass BEGIN' "$gtk4_dark_css" \
        || failures+=("gtk-dark.css came back but without its block")
else
    failures+=("removing the marker should revive gtk-dark.css, not leave it gone")
fi
grep -q 'aura-glass BEGIN' "$gtk3_css" \
    || failures+=("removing the marker should put the block back (gtk3)")
grep -q 'user-own-rule' "$gtk3_css" \
    || failures+=("coming back should still leave the user's own rule in gtk3.css")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'styling-off check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'styling-off check passed — splice, stand down (restore, move-aside, strip) across all four targets, idempotent, and all the way back\n'
