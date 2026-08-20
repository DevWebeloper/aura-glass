#!/usr/bin/env bash
# Moving a pre-rename install onto the current names, checked against fixture
# HOMEs. Nothing here touches the real HOME and nothing reaches the network.
#
# The case that matters most is 2. A user who installed under the old name and
# has already run post-rename code has a *wrong* backups/gtk4-gtk.css.orig — it
# was captured from a gtk.css that already carried our block. Their old config
# dir holds the correct .absent. If the merge lets both survive, restore() reads
# .orig first and a "clean" uninstall leaves every GTK4 app themed forever.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
pass() { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }

check() {  # check LABEL ACTUAL EXPECTED
    if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 — got '$2', want '$3'"; fi
}

# A legacy install: old config dir, old theme name, nothing under the new names.
make_legacy() {
    local h="$1"
    mkdir -p "$h/.config/tahoe-glass/backups" "$h/.cache/tahoe-glass/src" \
             "$h/.themes/Tahoe-Dark/gnome-shell"
    printf 'teal\n'   > "$h/.config/tahoe-glass/accent"
    printf 'frosted\n'> "$h/.config/tahoe-glass/glass-mode"
    : > "$h/.config/tahoe-glass/backups/gtk4-gtk.css.absent"
    printf 'pristine\n' > "$h/.config/tahoe-glass/backups/gnome-shell.css.orig"
    cat > "$h/.themes/Tahoe-Dark/index.theme" <<'EOF'
[X-GNOME-Metatheme]
Name=Tahoe-Dark
Type=X-GNOME-Metatheme
Encoding=UTF-8
GtkTheme=Tahoe-Dark
EOF
    : > "$h/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css"
}

# Run just the migration against a fixture HOME, with the real dconf/gsettings
# kept out of it — retheme_if_named is exercised on the real machine instead.
migrate_in() {
    local h="$1"; shift
    HOME="$h" DRY_RUN="${1:-0}" bash -c '
        set -euo pipefail
        REPO_ROOT="'"$REPO_ROOT"'"
        . "$REPO_ROOT/lib/common.sh"
        . "$REPO_ROOT/lib/steps.sh"
        . "$REPO_ROOT/lib/steps-migrate.sh"
        retheme_if_named() { :; }   # no dconf in a fixture
        migrate_legacy_names
    ' >/dev/null 2>&1
}

printf '\n1. legacy only\n'
h="$(mktemp -d)"; trap 'rm -rf "$h"' EXIT
make_legacy "$h"
migrate_in "$h"
check "old config dir gone"    "$([ -e "$h/.config/tahoe-glass" ] && echo yes || echo no)" "no"
check "new config dir present" "$([ -d "$h/.config/aura-glass" ] && echo yes || echo no)"  "yes"
check "accent carried over"    "$(cat "$h/.config/aura-glass/accent" 2>/dev/null)"         "teal"
check "backups carried over"   "$([ -e "$h/.config/aura-glass/backups/gtk4-gtk.css.absent" ] && echo yes || echo no)" "yes"
check "cache moved"            "$([ -d "$h/.cache/aura-glass/src" ] && echo yes || echo no)" "yes"
check "theme renamed"          "$([ -d "$h/.themes/Aura-Glass" ] && echo yes || echo no)"   "yes"
check "old theme gone"         "$([ -e "$h/.themes/Tahoe-Dark" ] && echo yes || echo no)"   "no"
check "index.theme Name"       "$(grep -c '^Name=Aura-Glass$' "$h/.themes/Aura-Glass/index.theme")"     "1"
check "index.theme GtkTheme"   "$(grep -c '^GtkTheme=Aura-Glass$' "$h/.themes/Aura-Glass/index.theme")" "1"

printf '\n2. both dirs — a polluted .orig must lose to the legacy .absent\n'
h2="$(mktemp -d)"; trap 'rm -rf "$h" "$h2"' EXIT
make_legacy "$h2"
mkdir -p "$h2/.config/aura-glass/backups"
# What a post-rename run recorded: the already-spliced override, as if pristine.
printf '/* >>> aura-glass BEGIN <<< */\n' > "$h2/.config/aura-glass/backups/gtk4-gtk.css.orig"
printf 'pristine\n' > "$h2/.config/aura-glass/backups/gnome-shell.css.orig"
printf 'purple\n'   > "$h2/.config/aura-glass/accent"
migrate_in "$h2"
check "polluted .orig removed"  "$([ -e "$h2/.config/aura-glass/backups/gtk4-gtk.css.orig" ] && echo yes || echo no)"   "no"
check "legacy .absent survives" "$([ -e "$h2/.config/aura-glass/backups/gtk4-gtk.css.absent" ] && echo yes || echo no)" "yes"
check "newer memo wins"         "$(cat "$h2/.config/aura-glass/accent" 2>/dev/null)" "purple"
check "old config dir gone"     "$([ -e "$h2/.config/tahoe-glass" ] && echo yes || echo no)" "no"

printf '\n3. a legacy styling-off must not flip a frosted desktop to solid\n'
h3="$(mktemp -d)"; trap 'rm -rf "$h" "$h2" "$h3"' EXIT
make_legacy "$h3"
: > "$h3/.config/tahoe-glass/styling-off"
mkdir -p "$h3/.config/aura-glass/backups"
printf 'pristine\n' > "$h3/.config/aura-glass/backups/gnome-shell.css.orig"
migrate_in "$h3"
check "styling-off not copied" "$([ -e "$h3/.config/aura-glass/styling-off" ] && echo yes || echo no)" "no"

printf '\n4. dry run changes nothing\n'
h4="$(mktemp -d)"; trap 'rm -rf "$h" "$h2" "$h3" "$h4"' EXIT
make_legacy "$h4"
migrate_in "$h4" 1
check "old config dir kept"  "$([ -d "$h4/.config/tahoe-glass" ] && echo yes || echo no)" "yes"
check "old theme kept"       "$([ -d "$h4/.themes/Tahoe-Dark" ] && echo yes || echo no)"  "yes"
check "no new theme dir"     "$([ -e "$h4/.themes/Aura-Glass" ] && echo yes || echo no)"  "no"

printf '\n5. second install — upstream recreates Tahoe-Dark beside our Aura-Glass\n'
h5="$(mktemp -d)"; trap 'rm -rf "$h" "$h2" "$h3" "$h4" "$h5"' EXIT
make_legacy "$h5"
rm -rf "$h5/.config/tahoe-glass" "$h5/.cache/tahoe-glass"
mkdir -p "$h5/.config/aura-glass/backups"
# Last run's theme, still being worn, plus the fresh one upstream just wrote.
mkdir -p "$h5/.themes/Aura-Glass/gnome-shell"
printf 'stale\n' > "$h5/.themes/Aura-Glass/gnome-shell/gnome-shell.css"
printf 'fresh\n' > "$h5/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css"
migrate_in "$h5"
check "upstream copy adopted"  "$(cat "$h5/.themes/Aura-Glass/gnome-shell/gnome-shell.css" 2>/dev/null)" "fresh"
check "old theme gone"         "$([ -e "$h5/.themes/Tahoe-Dark" ] && echo yes || echo no)" "no"
check "no .replacing left"     "$(find "$h5/.themes" -maxdepth 1 -name '*.replacing.*' | wc -l | tr -d ' ')" "0"
check "index.theme rewritten"  "$(grep -c '^Name=Aura-Glass$' "$h5/.themes/Aura-Glass/index.theme")" "1"

printf '\n6. the preset must not write the shell theme name\n'
check "no user-theme in core.ini" \
    "$(grep -c '^\[user-theme\]' "$REPO_ROOT/dconf/core.ini" || true)" "0"

printf '\n7. no new hardcoded theme literals\n'
# The legacy name is allowed only where it names something on a user's disk:
# the upstream constant, the migration itself, and the resolve-either fallbacks.
allowed=$(grep -rn 'Tahoe-Dark' "$REPO_ROOT/lib" "$REPO_ROOT/bin" \
    "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" 2>/dev/null \
    | grep -vc 'UPSTREAM_THEME_NAME=\|steps-migrate.sh\|^\S*:[0-9]*: *#\|THEME="Tahoe-Dark"\|\.themes/Tahoe-Dark" \]\|Tahoe-Dark".backup\|"\$HOME/.themes/Tahoe-Dark"' || true)
check "no stray Tahoe-Dark literals" "$allowed" "0"

printf '\n'
[ "$fail" = 0 ] && { printf '  all migration checks passed\n\n'; exit 0; }
printf '  migration checks FAILED\n\n'; exit 1
