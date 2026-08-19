#!/usr/bin/env bash
# Moving a pre-rename install onto the current names.
#
# The project was called tahoe-glass, and before that tahoe-tweaks. The rename
# to aura-glass replaced the strings but moved nothing, so an install made
# before it still keeps its settings in ~/.config/tahoe-glass while every
# current binary writes to ~/.config/aura-glass. That split is the thing this
# file closes, and it has to close it before anything reads either path.
#
# Separately: the GTK theme itself is upstream's, and upstream's installer
# hardcodes ~/.themes/Tahoe-Dark with no flag to change it. So the theme is
# renamed after that installer runs rather than instead of it.
#
# Sourced by install.sh, which calls migrate_legacy_names once, immediately
# after parse_flags and before the first $CONF_DIR read.

LEGACY_CONF="$HOME/.config/tahoe-glass"
LEGACY_CACHE="$HOME/.cache/tahoe-glass"

# Files whose meaning is "this file exists", not "this file says X". Copying one
# into a config dir that deliberately lacks it changes the answer rather than
# filling a gap — a stray styling-off would put a frosted desktop into solid
# mode on the next flagless run.
LEGACY_MARKERS=(styling-off)

# Point gtk-theme and the shell theme at the new name, but only where they still
# hold the old one. A solid-mode install has both cleared on purpose, and
# somebody may have picked their own shell theme since; neither is ours to
# overwrite on the way past.
retheme_if_named() {
    local old="$1"
    [ "${DRY_RUN:-0}" = 1 ] && { info "dry-run: repoint gtk-theme/user-theme $old -> $THEME_NAME"; return 0; }

    if [ "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" = "'$old'" ]; then
        gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME" 2>/dev/null || true
    fi
    if [ "$(dconf read /org/gnome/shell/extensions/user-theme/name 2>/dev/null)" = "'$old'" ]; then
        dconf write /org/gnome/shell/extensions/user-theme/name "'$THEME_NAME'" 2>/dev/null || true
    fi
}

# Upstream leaves a Tahoe-Dark.backup.<timestamp> behind every time it installs
# over an existing copy. Nothing has ever cleaned them and they are whole themes,
# so they add up. Anchored to upstream's own date +%Y%m%d-%H%M%S rather than a
# bare glob, because this is an rm -rf under ~/.themes.
sweep_theme_orphans() {
    local d
    for d in "$HOME/.themes/$UPSTREAM_THEME_NAME".backup.[0-9]*-[0-9]* \
             "$HOME/.themes/$THEME_NAME".replacing.*; do
        [ -e "$d" ] || continue
        run rm -rf "$d"
        [ "${DRY_RUN:-0}" = 1 ] || ok "removed orphaned $(basename "$d")"
    done
}

# Take upstream's Tahoe-Dark and make it ours. Idempotent and total: if the
# upstream name is on disk at all it gets adopted, whatever else is there.
adopt_theme_dir() {
    local themes="$HOME/.themes"
    local up="$themes/$UPSTREAM_THEME_NAME" ours="$themes/$THEME_NAME"

    [ -d "$up" ] || { sweep_theme_orphans; return 0; }

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: mv $up $ours (and rewrite index.theme)"
        retheme_if_named "$UPSTREAM_THEME_NAME"
        sweep_theme_orphans
        return 0
    fi

    # rename(2) will not replace a non-empty directory, so the old copy has to
    # go somewhere first. It moves aside rather than being deleted in place:
    # this is the theme the shell is currently wearing, and a run that dies
    # between an rm -rf and the mv would leave no theme of either name — a state
    # --settings-only cannot repair, which would strand anyone driving this from
    # the settings window.
    local aside="$ours.replacing.$$"
    [ -d "$ours" ] && mv "$ours" "$aside"
    mv "$up" "$ours"
    [ -d "$aside" ] && rm -rf "$aside"

    # Name= is what Tweaks and the Appearance list show; GtkTheme= is what
    # gtk-theme has to match. Nothing else in the tree names itself — no
    # absolute paths, no other self-references.
    if [ -f "$ours/index.theme" ]; then
        sed -i \
            -e "s/^Name=$UPSTREAM_THEME_NAME\$/Name=$THEME_NAME/" \
            -e "s/^GtkTheme=$UPSTREAM_THEME_NAME\$/GtkTheme=$THEME_NAME/" \
            "$ours/index.theme"
    fi

    # Back-to-back with the mv, with nothing in between: until these are written
    # the shell is pointed at a directory that no longer exists.
    retheme_if_named "$UPSTREAM_THEME_NAME"
    ok "theme adopted as $THEME_NAME"
    sweep_theme_orphans
}

# True when the aura-glass config dir exists but has never really been used.
# seed_glass_mode mkdir -p's modes/<mode>/ with no dry-run guard, so even
# `--dry-run` on a legacy machine leaves a decoy behind. An empty backups/ is
# the honest signal: nothing has installed through this directory yet.
conf_is_decoy() {
    [ -d "$1" ] || return 0
    [ -z "$(ls -A "$1/backups" 2>/dev/null || true)" ]
}

# backups/ records what the machine looked like before aura-glass touched it,
# and it is the only thing here that cannot be regenerated. The legacy copy is
# always the truthful one: a legacy user who has already run post-rename code
# has a *wrong* aura-glass copy, because install_theme's backup_once ran against
# a gtk.css that already carried our block and recorded it as if pristine.
#
# .orig and .absent are mutually exclusive per name and restore() reads .orig
# first, so letting both survive is what would turn a clean uninstall into one
# that copies the themed override back and leaves every GTK4 app themed.
merge_backups() {
    local from="$1" to="$2" f base name
    [ -d "$from" ] || return 0
    mkdir -p "$to"

    for f in "$from"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        cp -a "$f" "$to/$base"

        case "$base" in
            *.orig)   name="${base%.orig}";   rm -f "$to/$name.absent" ;;
            *.absent) name="${base%.absent}"; rm -f "$to/$name.orig"   ;;
        esac
    done
}

# Copy-if-missing, skipping the presence-markers. Used for the current-state
# memos, where the aura-glass copy is the newer truth and legacy only fills gaps.
merge_fill_gaps() {
    local from="$1" to="$2" f base m skip
    for f in "$from"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        [ "$base" = backups ] && continue

        skip=0
        for m in "${LEGACY_MARKERS[@]}"; do
            [ "$base" = "$m" ] && skip=1
        done
        [ "$skip" = 1 ] && continue

        [ -e "$to/$base" ] && continue
        cp -a "$f" "$to/$base"
    done
}

# Copy-then-remove rather than a move per file: a run that dies half way has to
# leave the legacy directory whole, so the next run can start over.
migrate_dir() {
    local from="$1" to="$2" what="$3"
    [ -d "$from" ] || return 0

    if [ ! -d "$to" ]; then
        run mv "$from" "$to"
        [ "${DRY_RUN:-0}" = 1 ] || ok "moved $what to $(basename "$to")"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: merge $from into $to"
        return 0
    fi

    # A decoy has nothing worth preferring, so the legacy side wins outright.
    if conf_is_decoy "$to"; then
        merge_backups "$from/backups" "$to/backups"
        local f base
        for f in "$from"/*; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            [ "$base" = backups ] && continue
            cp -a "$f" "$to/$base"
        done
    else
        merge_backups "$from/backups" "$to/backups"
        merge_fill_gaps "$from" "$to"
    fi

    rm -rf "$from"
    ok "merged $what into $(basename "$to")"
}

migrate_legacy_names() {
    local legacy_conf=0 legacy_theme=0
    [ -d "$LEGACY_CONF" ] && legacy_conf=1
    [ -d "$HOME/.themes/$UPSTREAM_THEME_NAME" ] && legacy_theme=1

    if [ "$legacy_conf" = 0 ] && [ "$legacy_theme" = 0 ] \
       && [ ! -d "$LEGACY_CACHE" ]; then
        return 0
    fi

    step "Migrating a pre-rename install"

    # A dry run must not move anything, but it still has to report on the
    # settings the user actually has. Reading from the legacy paths is what
    # keeps `--dry-run` on an un-migrated machine from printing defaults, and
    # what keeps the --settings-only guard from deciding nothing is installed.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        if [ "$legacy_conf" = 1 ] && conf_is_decoy "$CONF_DIR"; then
            CONF_DIR="$LEGACY_CONF"
            BACKUP_DIR="$CONF_DIR/backups"
            info "dry-run: reading settings from $CONF_DIR"
        fi
        [ -d "$LEGACY_CACHE/src" ] && [ ! -d "$SRC_CACHE" ] && SRC_CACHE="$LEGACY_CACHE/src"
    fi

    migrate_dir "$LEGACY_CONF"  "$HOME/.config/aura-glass" "settings"
    # The whole cache, not just src/ — preview profiles and the GPU log sit
    # beside it. The build directories go: meson bakes absolute paths into
    # build.ninja, so a moved one is broken anyway, and install_rounded_blur
    # sets its own up fresh on every run.
    migrate_dir "$LEGACY_CACHE" "$HOME/.cache/aura-glass"  "cache"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        rm -rf "$HOME/.cache/aura-glass"/src/*/build 2>/dev/null || true
    fi

    adopt_theme_dir
}
