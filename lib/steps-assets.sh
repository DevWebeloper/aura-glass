# shellcheck shell=bash
# aura-glass — icon and cursor themes.
#
# The accent drives the icon colour but is deliberately not the only thing that
# can: --icons takes a pack and a colour of its own, because wanting purple
# folders under a pink accent is an ordinary thing to want.
#
# Packs also disagree about how they spell a light/dark pair — Colloid ships
# -Light and -Dark, Reversal ships the bare name plus -dark — so rather than
# teach every caller both conventions, icon_variant asks the filesystem.
#
# Sourced by install.sh.

# GNOME's accent enum -> Colloid's folder-colour variant. Colloid calls blue
# "default" on the command line and leaves it out of the theme name.
accent_to_colloid_arg() {
    case "$1" in
        blue)   echo default ;;
        slate)  echo grey ;;
        teal|green|yellow|orange|red|pink|purple) echo "$1" ;;
        *)      echo default ;;
    esac
}
accent_to_colloid_name() {
    case "$1" in
        blue)  echo "Colloid-Dark" ;;
        slate) echo "Colloid-Grey-Dark" ;;
        teal)  echo "Colloid-Teal-Dark" ;;
        *)     echo "Colloid-${1^}-Dark" ;;
    esac
}

# GNOME's accent enum -> Reversal's colour. The two sets do not line up: Reversal
# has no teal, no yellow and no slate, and has browns and greys the accent enum
# does not. So three accents map to a neighbour rather than to themselves.
#
# This exists because `--icons reversal-$ACCENT` was being built by hand in the
# interactive wizard, and three of the nine accents made a colour Reversal does
# not ship — picking teal, yellow or slate and then choosing Reversal ended the
# install on "unknown Reversal colour". Bare `reversal` had the opposite problem:
# it fell back to purple whatever the accent was.
accent_to_reversal() {
    case "$1" in
        teal)   echo cyan ;;    # nearest Reversal has; no teal
        yellow) echo orange ;;  # no yellow either, and orange is the warm one
        slate)  echo grey ;;
        blue|green|orange|red|pink|purple) echo "$1" ;;
        *)      echo purple ;;
    esac
}

# ---------------------------------------------------------------- preflight --

# The icon set, minus any light/dark suffix. Everything downstream — the
# gsettings key and the light/dark agent — works from this one name.
#
# --icons takes either "colloid", which follows --accent, or a pack and colour
# like "reversal-purple". Folder colour and accent are separate on purpose:
# wanting purple folders under a pink accent is a perfectly ordinary thing to
# want, and tying them together would make it unsayable.
icon_base() {
    case "${ICONS:-colloid}" in
        colloid)
            local n; n="$(accent_to_colloid_name "$ACCENT")"
            n="${n%-Dark}"; n="${n%-Light}"
            printf '%s\n' "$n" ;;
        reversal)        printf 'Reversal\n' ;;
        reversal-*)      printf 'Reversal-%s\n' "${ICONS#reversal-}" ;;
        *)               printf '%s\n' "$ICONS" ;;
    esac
}

# Packs disagree about how they spell the pair: Colloid ships -Light/-Dark,
# Reversal ships the bare name plus -dark. Rather than teach every caller the
# conventions, ask the filesystem which of them exists.
icon_variant() {
    local base="$1" want="$2" c   # want: Dark | Light
    for c in "$base-$want" "$base-$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" "$base"; do
        if [ -d "$HOME/.local/share/icons/$c" ] || [ -d "/usr/share/icons/$c" ]; then
            printf '%s\n' "$c"; return 0
        fi
    done
    return 1
}

# One flat 16x16 symbolic arrow. viewBox is not optional: without it the width
# and height are the only size the file has, so the copy written into the @2x
# directory cannot scale to the size that directory exists to serve.
pan_svg() {
    printf "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'><path d='%s' fill='currentColor'/></svg>\n" "$1"
}

# Reversal's own pan-*.svg carry a group transform that was never baked into
# the path data underneath it. librsvg applies the transform and draws them
# correctly; GTK4's symbolic loader re-serialises the path and drops it, so
# every chevron the theme draws — expander rows, dropdowns, the path bar —
# came out rotated. These are the same four arrows with the transform already
# applied, so there is nothing left for a loader to lose.
#
# The -rtl pair is mirrored on purpose: start points right and end points left
# in a right-to-left locale, which is the reverse of the names above them.
#
# This overwrites files the Reversal installer laid down, and nothing here puts
# them back. `uninstall.sh --assets` removes the icon theme whole, which is the
# counterpart — the patched files go with it.
patch_reversal_symbolics() {
    local name="$1" dir sub found=0
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: rewrite pan-*.svg and lock symbolics under $name"
        return 0
    fi
    for dir in "$HOME/.local/share/icons/$name" "$HOME/.local/share/icons/$name-dark" \
               "$HOME/.local/share/icons/$name-Light" "$HOME/.local/share/icons/$name-Dark"; do
        [ -d "$dir" ] || continue
        for sub in "actions/symbolic" "actions@2x/symbolic"; do
            [ -d "$dir/$sub" ] || continue
            found=$((found + 1))
            pan_svg 'M 13,6 8,11 3,6 Z'  > "$dir/$sub/pan-down-symbolic.svg"
            pan_svg 'M 13,10 8,5 3,10 Z' > "$dir/$sub/pan-up-symbolic.svg"
            pan_svg 'M 10,13 5,8 10,3 Z' > "$dir/$sub/pan-start-symbolic.svg"
            pan_svg 'M 6,13 11,8 6,3 Z'  > "$dir/$sub/pan-end-symbolic.svg"
            pan_svg 'M 6,13 11,8 6,3 Z'  > "$dir/$sub/pan-start-symbolic-rtl.svg"
            pan_svg 'M 10,13 5,8 10,3 Z' > "$dir/$sub/pan-end-symbolic-rtl.svg"

            # Solid lock icon (GNOME Shell quicksettings & lock screen)
            pan_svg 'M 8,1 C 5.8,1 4,2.8 4,5 v 2 C 2.9,7 2,7.9 2,9 v 5 c 0,0.6 0.4,1 1,1 h 10 c 0.6,0 1,-0.4 1,-1 V 9 C 14,7.9 13.1,7 12,7 V 5 C 12,2.8 10.2,1 8,1 Z m 0,2 c 1.1,0 2,0.9 2,2 v 2 H 6 V 5 C 6,3.9 6.9,3 8,3 Z' > "$dir/$sub/system-lock-screen-symbolic.svg"
            pan_svg 'M 8,1 C 5.8,1 4,2.8 4,5 v 2 C 2.9,7 2,7.9 2,9 v 5 c 0,0.6 0.4,1 1,1 h 10 c 0.6,0 1,-0.4 1,-1 V 9 C 14,7.9 13.1,7 12,7 V 5 C 12,2.8 10.2,1 8,1 Z m 0,2 c 1.1,0 2,0.9 2,2 v 2 H 6 V 5 C 6,3.9 6.9,3 8,3 Z' > "$dir/$sub/lock-symbolic.svg"
            pan_svg 'M 8,1 C 5.8,1 4,2.8 4,5 v 2 C 2.9,7 2,7.9 2,9 v 5 c 0,0.6 0.4,1 1,1 h 10 c 0.6,0 1,-0.4 1,-1 V 9 C 14,7.9 13.1,7 12,7 V 5 C 12,2.8 10.2,1 8,1 Z m 0,2 c 1.1,0 2,0.9 2,2 v 2 H 6 V 5 C 6,3.9 6.9,3 8,3 Z' > "$dir/$sub/screen-lock-symbolic.svg"
        done
        for sub in "apps/symbolic" "apps@2x/symbolic"; do
            [ -d "$dir/$sub" ] || continue
            pan_svg 'M 8,1 C 5.8,1 4,2.8 4,5 v 2 C 2.9,7 2,7.9 2,9 v 5 c 0,0.6 0.4,1 1,1 h 10 c 0.6,0 1,-0.4 1,-1 V 9 C 14,7.9 13.1,7 12,7 V 5 C 12,2.8 10.2,1 8,1 Z m 0,2 c 1.1,0 2,0.9 2,2 v 2 H 6 V 5 C 6,3.9 6.9,3 8,3 Z' > "$dir/$sub/org.gnome.Settings-system-lock-screen-symbolic.svg"
        done
        for sub in "status/symbolic" "status@2x/symbolic"; do
            [ -d "$dir/$sub" ] || continue
            pan_svg 'M 8,1 C 5.8,1 4,2.8 4,5 v 2 C 2.9,7 2,7.9 2,9 v 5 c 0,0.6 0.4,1 1,1 h 10 c 0.6,0 1,-0.4 1,-1 V 9 C 14,7.9 13.1,7 12,7 V 5 C 12,2.8 10.2,1 8,1 Z m 0,2 c 1.1,0 2,0.9 2,2 v 2 H 6 V 5 C 6,3.9 6.9,3 8,3 Z' > "$dir/$sub/changes-prevent-symbolic.svg"
        done
        # Remove any misplaced full-color scalable SVGs incorrectly named *-symbolic
        rm -f "$dir/apps/scalable/system-lock-screen-symbolic.svg" \
              "$dir/apps/scalable/applications-system-symbolic.svg" \
              "$dir/apps/scalable/mark-location-symbolic.svg"
        # GTK reads icon-theme.cache in preference to the directory it describes,
        # so a theme that has one keeps serving the old arrows however many times
        # the files above are rewritten. Reversal's installer leaves one behind.
        if [ -f "$dir/icon-theme.cache" ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -qft "$dir" 2>/dev/null || true
        fi
    done
    # A silent no-op is the failure mode that matters here: the pack reorganises
    # its directories, every path misses, and the chevrons stay wrong with
    # nothing said about it.
    [ "$found" -gt 0 ] || warn "no symbolic directory found under $name — chevrons left unpatched"
}

install_reversal() {
    local color="${ICONS#reversal}"; color="${color#-}"
    # Bare `reversal` follows the accent, the way bare `colloid` does. It used to
    # mean purple regardless, which made the family unusable as a default.
    [ -n "$color" ] || color="$(accent_to_reversal "$ACCENT")"
    local name="Reversal-$color"

    step "Installing the Reversal icon theme ($color)"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
        patch_reversal_symbolics "$name"
        skip "$name already installed"
        return 0
    fi

    local src="$SRC_CACHE/Reversal-icon-theme"
    clone_pinned "$REVERSAL_REPO" "$REVERSAL_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -t $color"
    else
        ( cd "$src" && ./install.sh -t "$color" ) >/dev/null \
            || die "the Reversal installer failed"
        patch_reversal_symbolics "$name"
    fi
    ok "$name"
}

install_icons() {
    case "${ICONS:-colloid}" in
        reversal|reversal-*) install_reversal; return ;;
    esac

    step "Installing the Colloid icon theme ($ACCENT)"

    local name; name="$(accent_to_colloid_name "$ACCENT")"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
        skip "$name already installed"
        return 0
    fi

    local src="$SRC_CACHE/Colloid-icon-theme"
    clone_pinned "$COLLOID_REPO" "$COLLOID_REF" "$src"

    # No -d: unprivileged runs default to ~/.local/share/icons, which keeps
    # this step out of /usr like every other one.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -t $(accent_to_colloid_arg "$ACCENT")"
    else
        ( cd "$src" && ./install.sh -t "$(accent_to_colloid_arg "$ACCENT")" ) >/dev/null \
            || die "the Colloid installer failed"
    fi
    ok "$name"
}

install_cursors() {
    # Adwaita's cursors ship with GNOME itself, so there is nothing to fetch,
    # nothing to keep pinned, and they are crisper and better hinted at every
    # size than the MacTahoe set. --cursors mactahoe asks for the old ones.
    if [ "${CURSORS:-adwaita}" = adwaita ]; then
        step "Cursors"
        skip "using the stock Adwaita cursors (--cursors mactahoe for the macOS set)"
        return 0
    fi

    step "Installing MacTahoe cursors"

    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark/cursors" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark/cursors" ]; }; then
        skip "MacTahoe-dark cursors already installed"
        return 0
    fi

    local src="$SRC_CACHE/MacTahoe-icon-theme"
    clone_pinned "$MACTAHOE_REPO" "$MACTAHOE_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh"
    else
        # The cursors ship inside the icon theme, so the icon theme comes with
        # them. Colloid still supplies the app icons — only the pointer changes.
        ( cd "$src" && ./install.sh ) >/dev/null || die "the MacTahoe installer failed"
    fi
    ok "MacTahoe-dark"
}

# --------------------------------------------------------------- css + dconf --
