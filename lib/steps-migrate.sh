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
# filling a gap — a stray styling-off would have migrate_solid_era treat a
# frosted desktop as a solid one.
LEGACY_MARKERS=(styling-off)

# Point gtk-theme and the shell theme at the new name, but only where they still
# hold the old one. Somebody may have picked their own shell theme since, and
# that is not ours to overwrite on the way past.
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
# Versions before the dry-run drawer fix (KI-08) let seed_glass_mode create
# modes/<mode>/ even under `--dry-run`, so a legacy machine can still carry that
# decoy. An empty backups/ is the honest signal: nothing has installed through
# this directory yet.
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
    # build.ninja, so a moved one is broken anyway.
    migrate_dir "$LEGACY_CACHE" "$HOME/.cache/aura-glass"  "cache"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        rm -rf "$HOME/.cache/aura-glass"/src/*/build 2>/dev/null || true
    fi

    adopt_theme_dir
}

# ---- out of the three-mode era ------------------------------------------

# Releases before Performance had a third mode, solid, that stood the theme
# down instead of styling it: a styling-off marker, the four targets restored
# or moved aside into backups/<name>.stood-down, gtk-theme and the shell theme
# reset, and this project's extensions switched off with a record of which in
# modes/solid/disabled-extensions. A fourth, transparent, was folded into
# frosted. Both are gone (KI-15), so a machine still carrying either is put
# back here, once, before anything reads the glass mode:
#
# - solid becomes performance, the mode that replaced it (no blur, still
#   themed), and transparent becomes frosted. The memo is all that changes;
#   the run then resolves and applies that mode like any other.
# - a target moved aside comes back, since aura-glass-apply no longer knows
#   the .stood-down names. One already recreated since keeps the newer file.
# - the extensions solid switched off come back on, exactly the recorded ones.
# - the marker and both retired drawers go.
#
# Not under remembering(): it is the machine's state being corrected, not a
# choice being memoed, and the adaptive worker's runs have to see the same
# corrected state. Only a dry run or a preview leaves it alone.
migrate_solid_era() {
    local mode="" name target
    [ -r "$CONF_DIR/glass-mode" ] && mode="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
    case "$mode" in solid|transparent) ;; *) mode="" ;; esac
    if [ -z "$mode" ] && [ ! -e "$CONF_DIR/styling-off" ] \
       && [ ! -d "$CONF_DIR/modes/solid" ] && [ ! -d "$CONF_DIR/modes/transparent" ] \
       && ! compgen -G "$CONF_DIR/backups/*.stood-down" >/dev/null; then
        return 0
    fi

    step "Migrating from the retired solid mode"
    if [ "${DRY_RUN:-0}" = 1 ] || [ "${PREVIEW_MODE:-0}" = 1 ]; then
        info "dry-run: retire solid/transparent (memo, marker, drawers, stood-down targets)"
        return 0
    fi

    case "$mode" in
        solid)       printf 'performance\n' > "$CONF_DIR/glass-mode"; ok "glass mode solid is now performance" ;;
        transparent) printf 'frosted\n'     > "$CONF_DIR/glass-mode"; ok "glass mode transparent is now frosted" ;;
    esac

    for name in gnome-shell.css gtk4-gtk.css gtk4-gtk-dark.css gtk3-gtk.css; do
        [ -f "$CONF_DIR/backups/$name.stood-down" ] || continue
        case "$name" in
            gnome-shell.css)   target="$HOME/.themes/$THEME_NAME/gnome-shell/gnome-shell.css" ;;
            gtk4-gtk.css)      target="$HOME/.config/gtk-4.0/gtk.css" ;;
            gtk4-gtk-dark.css) target="$HOME/.config/gtk-4.0/gtk-dark.css" ;;
            gtk3-gtk.css)      target="$HOME/.config/gtk-3.0/gtk.css" ;;
        esac
        if [ -e "$target" ]; then
            rm -f "$CONF_DIR/backups/$name.stood-down"
        else
            mkdir -p "$(dirname "$target")"
            mv -f "$CONF_DIR/backups/$name.stood-down" "$target"
            ok "brought back $target"
        fi
    done

    restore_stood_down_extensions
    rm -rf "$CONF_DIR/styling-off" "$CONF_DIR/modes/solid" "$CONF_DIR/modes/transparent"
    ok "solid-mode leftovers removed"
}

# The extensions solid switched off, in the order it wrote them down. A UUID no
# longer installed is skipped; one the running Wayland shell will not load goes
# into enabled-extensions for the next session, as enable_extensions does.
restore_stood_down_extensions() {
    local record="$CONF_DIR/modes/solid/disabled-extensions" u back=0
    [ -r "$record" ] || return 0
    while IFS= read -r u; do
        [ -n "$u" ] || continue
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            skip "$u is no longer installed"
            continue
        fi
        if gnome-extensions enable "$u" 2>/dev/null; then
            back=$((back + 1))
        elif enqueue_extension "$u"; then
            ok "$u queued — active after logout"
            back=$((back + 1))
        else
            warn "could not switch $u back on"
        fi
    done < "$record"
    ok "$back extension(s) back on"
}

# --reset: forget every remembered choice, so this run and the wizard it opens
# start from the defaults a first install would. What the settings window's
# "Reset to defaults" runs, together with --force (reinstall everything,
# core.ini included) and --interactive (ask the questions again).
#
# Choices only. What records the state of the machine — repo-path, patch and
# build stamps, bms-ref, the GDM records, the preview journal, backups/ and the
# installed sheet copies — stays, because forgetting it would make this run
# misjudge what is installed rather than what was chosen.
#
# Moved, not deleted, into backups/reset-<stamp>/: a reset someone regrets is a
# directory to copy back. Before the wizard, because both wizards pre-fill from
# these memos and a reset that showed the old answers would not look like one;
# restore_reset_choices puts them back if the wizard is then cancelled, since
# nothing was installed to go with the defaults.
RESET_MEMOS=(
    glass-mode modes accent radius-preset radius-custom
    app-transparency app-opacity app-tint-color shell-tint-color
    notification-opacity blur-strength popup-brightness window-brightness grain
    glass-style liquid-windows fullscreen-blur titlebutton-style window-buttons
    window-blur app-blur-scope app-blur-allow app-blur-block
    popup-blur notification-blur
    adaptive-profile adaptive-fullscreen-apps
    icon-pack icons cursor-pack cursor-size font
    update-check update-channel rounded-blur-choice
    extension-pack extension-catalog osd bms-source
)

reset_remembered_choices() {
    [ "${RESET:-0}" = 1 ] || return 0
    step "Resetting to defaults"
    RESET_DIR="$BACKUP_DIR/reset-$(date +%Y%m%d-%H%M%S)"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: would move the remembered choices to $RESET_DIR"
        return 0
    fi
    mkdir -p "$RESET_DIR"
    local name moved=0
    for name in "${RESET_MEMOS[@]}"; do
        if [ -e "$CONF_DIR/$name" ]; then
            mv "$CONF_DIR/$name" "$RESET_DIR/"
            moved=$((moved + 1))
        fi
    done
    ok "$moved remembered choice(s) moved to $RESET_DIR — everything starts from its default"
}

restore_reset_choices() {
    [ -n "${RESET_DIR:-}" ] && [ -d "$RESET_DIR" ] || return 0
    local path
    for path in "$RESET_DIR"/* "$RESET_DIR"/.[!.]*; do
        [ -e "$path" ] || continue
        [ -e "$CONF_DIR/${path##*/}" ] || mv "$path" "$CONF_DIR/"
    done
    rmdir "$RESET_DIR" 2>/dev/null || true
    info "nothing was reset — your choices are as they were"
}
