# shellcheck shell=bash
# tahoe-glass — icon and cursor themes.
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

install_reversal() {
    local color="${ICONS#reversal}"; color="${color#-}"
    [ -n "$color" ] || color=purple
    local name="Reversal-$color"

    step "Installing the Reversal icon theme ($color)"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
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
