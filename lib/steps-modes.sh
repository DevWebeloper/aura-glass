# shellcheck shell=bash
# aura-glass — the glass modes (frosted and performance).
#
# A mode is not a fourth kind of setting — it is a name for a combination of the
# blur and transparency flags install.sh already has, plus a drawer to
# keep each combination's own tuning in. Everything here therefore resolves into
# those flags and then gets out of the way: nothing downstream of this file
# knows a mode exists.
#
# Precedence, highest first: a flag the user typed, then --glass-mode, then the
# remembered mode, then a mode derived from the state the flags leave behind.
# The rule is the ordinary one — an explicit answer beats an inferred one — and
# it is why apply_glass_mode tests every *_EXPLICIT before it moves anything.
# Frosted and performance apply that by leaving an explicit sub-flag's answer
# alone.

# The mode the resolved state amounts to, which is what gets remembered.
glass_mode_from_state() {
    if [ "${GLASS_MODE:-}" = performance ]; then
        printf 'performance\n'
    else
        printf 'frosted\n'
    fi
}

resolve_glass_mode() {
    if [ -n "${GLASS_MODE_EXPLICIT:-}" ]; then
        case " $VALID_GLASS_MODES " in
            *" $GLASS_MODE "*) ;;
            *) die "unknown --glass-mode '$GLASS_MODE' — pick one of: $VALID_GLASS_MODES" ;;
        esac
        return 0
    fi

    # Explicit flags typed by the user beat the remembered mode. Asking for
    # window blur or general blur is asking for frosted mode; asking for no-blur
    # is asking for performance mode.
    if [ "${WANT_WINDOW_BLUR:-}" = 1 ] && [ -n "${WINDOW_BLUR_EXPLICIT:-}" ]; then
        GLASS_MODE="frosted"
        return 0
    elif [ "${WANT_BLUR:-}" = 1 ] && [ -n "${BLUR_EXPLICIT:-}" ]; then
        GLASS_MODE="frosted"
        return 0
    elif [ "${WANT_BLUR:-}" = 0 ] && [ -n "${BLUR_EXPLICIT:-}" ]; then
        GLASS_MODE="performance"
        return 0
    fi

    if [ -r "$CONF_DIR/glass-mode" ]; then
        GLASS_MODE="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
        case " $VALID_GLASS_MODES " in
            *" $GLASS_MODE "*) return 0 ;;
        esac
    fi
    GLASS_MODE=""      # nothing to go on; apply_glass_mode leaves the flags be
}

# The table in the design doc, in code. Only ever writes a value whose flag was
# not given: an explicit flag overrules the mode.
apply_glass_mode() {
    case "${GLASS_MODE:-}" in
        frosted)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=1
            [ -n "${WINDOW_BLUR_EXPLICIT:-}" ] || WANT_WINDOW_BLUR=1
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=1
            ;;
        performance)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=0
            if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ]; then
                WANT_WINDOW_BLUR=0
                APP_BLUR_SCOPE="none"
            fi
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=0
            ;;
        *)  # No mode to apply: a run driven by bare flags, on a machine that
            # has never been told about modes. The flags stand as given.
            ;;
    esac
}

# Written after the run has resolved, so the memo holds what was applied rather
# than what was asked for.
remember_glass_mode() {
    GLASS_MODE="$(glass_mode_from_state)"
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$GLASS_MODE" > "$CONF_DIR/glass-mode"
    save_glass_mode_memos
}

# ---- the per-mode drawer ------------------------------------------------

# Every mode keeps the settings that belong to it. The top-level memos stay the
# live state — install_transparency_css, apply_app_tint_color and the settings
# window all read those, and none of them learn about modes — so these are an
# archive that the mode switch restores from, not a second source of truth.
#
# MODES_ROOT is where the drawers live: $CONF_DIR/modes, except on a dry run.
# A dry run has to resolve exactly as the real run would, and that resolution
# reads the drawer seed_glass_mode writes — so instead of skipping the seed,
# install.sh points this at a scratch copy that is thrown away on exit. Same
# answers, nothing left in $CONF_DIR (KI-08).
modes_root() { printf '%s\n' "${MODES_ROOT:-$CONF_DIR/modes}"; }
mode_memo_path() { printf '%s/%s/%s\n' "$(modes_root)" "${GLASS_MODE:-frosted}" "$1"; }

mode_memo_read() {   # KEY DEFAULT
    local f; f="$(mode_memo_path "$1")"
    if [ -r "$f" ]; then cat "$f" 2>/dev/null || printf '%s\n' "$2"
    else printf '%s\n' "$2"; fi
}

mode_memo_write() {  # KEY VALUE
    mkdir -p "$(modes_root)/${GLASS_MODE:-frosted}"
    printf '%s\n' "$2" > "$(mode_memo_path "$1")"
}

# What a mode starts life with. Read from the top-level memos where they exist,
# so an install that predates modes keeps the tuning it is wearing and finds it
# in the tab it belongs to; from the constants only where there is nothing to
# read. Transparent is the exception that proves it: with no blur behind the
# window the wallpaper is what the text sits on, so it starts darker, and a
# level of 0 is not a state this mode has.
seed_glass_mode() {
    local dir; dir="$(modes_root)/${GLASS_MODE:-frosted}"
    [ -d "$dir" ] && return 0
    mkdir -p "$dir"

    local disk_level disk_app disk_shell disk_strength disk_scope disk_popup
    local disk_brightness disk_popup_opacity entry surface legacy
    disk_level="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    disk_app="$(cat "$CONF_DIR/app-tint-color" 2>/dev/null || true)"
    disk_shell="$(cat "$CONF_DIR/shell-tint-color" 2>/dev/null || true)"
    disk_strength="$(cat "$CONF_DIR/blur-strength" 2>/dev/null || true)"
    disk_scope="$(cat "$CONF_DIR/app-blur-scope" 2>/dev/null || true)"
    disk_popup="$(cat "$CONF_DIR/popup-blur" 2>/dev/null || true)"
    disk_brightness="$(cat "$CONF_DIR/blur-brightness" 2>/dev/null || true)"
    disk_popup_opacity="$(cat "$CONF_DIR/popup-opacity" 2>/dev/null || true)"

    if [ "${GLASS_MODE:-}" = performance ]; then
        mode_memo_write app-transparency "1.00"
        mode_memo_write app-tint-color   "#000000"
        mode_memo_write shell-tint-color "#000000"
        mode_memo_write app-blur-scope   "none"
        mode_memo_write popup-blur       "0"
    else
        # With no memo to inherit, the same level install.sh's own resolution
        # falls back to — 0.95 without window blur, 0.90 with it. Seeding 0
        # here made a fresh `--glass-mode frosted` come out opaque while a
        # flagless run on the same machine came out at 0.90.
        local fresh_level=0.90
        [ "${WANT_WINDOW_BLUR:-1}" = 0 ] && fresh_level=0.95
        mode_memo_write app-transparency "${disk_level:-$fresh_level}"
        mode_memo_write app-tint-color   "${disk_app:-#000000}"
        mode_memo_write shell-tint-color "${disk_shell:-#000000}"
        mode_memo_write app-blur-scope   "${disk_scope:-all}"
        mode_memo_write blur-strength    "${disk_strength:-100}"
        mode_memo_write blur-brightness  "${disk_brightness:-100}"
        mode_memo_write popup-opacity    "${disk_popup_opacity:-main}"
        mode_memo_write popup-blur       "${disk_popup:-1}"
        # Each surface's own blur, from the top-level memos (and the two
        # brightness memos an earlier release wrote under other names) the
        # same way resolve_blur_pipelines reads them.
        for entry in $BLUR_SURFACES; do
            surface="${entry%%:*}"
            legacy="$(surface_brightness_legacy "$surface")"
            mode_memo_write "$surface-blur-strength" \
                "$(surface_memo_read "$CONF_DIR" "$surface-blur-strength")"
            # shellcheck disable=SC2086 # the legacy name and its defaults, split
            mode_memo_write "$surface-blur-brightness" \
                "$(surface_memo_read "$CONF_DIR" "$surface-blur-brightness" $legacy)"
        done
    fi
}

# The drawer into this run's variables. Only where the flag was not given, on
# the same precedence rule apply_glass_mode follows.
load_glass_mode_memos() {
    [ -n "${GLASS_MODE:-}" ] || return 0

    # A value install.sh would refuse is treated as an empty drawer rather than
    # passed along: the flag it would become dies in the parser, which is a
    # failure a long way from the file that caused it.
    local def_t=0
    [ "${GLASS_MODE}" = performance ] && def_t=1.00
    local level; level="$(mode_memo_read app-transparency "$def_t")"
    case "$level" in
        0|0.[0-9][0-9]|1.00) ;;
        *) warn "$(mode_memo_path app-transparency) holds '$level' — reseeding this mode"
           rm -rf "$(modes_root)/$GLASS_MODE"
           seed_glass_mode ;;
    esac

    if [ -z "${APP_TRANSPARENCY_EXPLICIT:-}" ]; then
        APP_TRANSPARENCY="$(mode_memo_read app-transparency "$def_t")"
        if [ "$GLASS_MODE" = performance ] && [ "$APP_TRANSPARENCY" = 1.00 ]; then
            APP_OPACITY=255
        else
            APP_OPACITY="$(python3 -c "print(round(float('$APP_TRANSPARENCY') * 255))" 2>/dev/null || echo 255)"
        fi
        APP_OPACITY_EXPLICIT=1
    fi

    [ -n "${APP_TINT_COLOR_EXPLICIT:-}" ] || [ -n "${APP_TINT_COLOR:-}" ] \
        || APP_TINT_COLOR="$(mode_memo_read app-tint-color '#000000')"
    [ -n "${SHELL_TINT_COLOR_EXPLICIT:-}" ] || [ -n "${SHELL_TINT_COLOR:-}" ] \
        || SHELL_TINT_COLOR="$(mode_memo_read shell-tint-color '#000000')"

    if [ "${GLASS_MODE}" = frosted ]; then
        [ -n "${BLUR_STRENGTH:-}" ] \
            || BLUR_STRENGTH="$(mode_memo_read blur-strength 100)"
        [ -n "${BLUR_BRIGHTNESS:-}" ] \
            || BLUR_BRIGHTNESS="$(mode_memo_read blur-brightness 100)"
        [ -n "${POPUP_OPACITY:-}" ] \
            || POPUP_OPACITY="$(mode_memo_read popup-opacity main)"
        local entry surface var bvar legacy dir
        dir="$(modes_root)/$GLASS_MODE"
        for entry in $BLUR_SURFACES; do
            surface="${entry%%:*}"
            var="$(printf '%s' "$surface" | tr '[:lower:]' '[:upper:]')_BLUR_STRENGTH"
            bvar="$(printf '%s' "$surface" | tr '[:lower:]' '[:upper:]')_BRIGHTNESS"
            [ -n "${!var:-}" ] \
                || printf -v "$var" '%s' "$(surface_memo_read "$dir" "$surface-blur-strength")"
            legacy="$(surface_brightness_legacy "$surface")"
            # shellcheck disable=SC2086 # the legacy name and its defaults, split
            [ -n "${!bvar:-}" ] \
                || printf -v "$bvar" '%s' "$(surface_memo_read "$dir" "$surface-blur-brightness" $legacy)"
        done
        if [ -z "${POPUP_BLUR_EXPLICIT:-}" ]; then
            WANT_POPUP_BLUR="$(mode_memo_read popup-blur 1)"
            POPUP_BLUR_EXPLICIT=1
        fi
        if [ -z "${APP_BLUR_SCOPE_EXPLICIT:-}" ]; then
            APP_BLUR_SCOPE="$(mode_memo_read app-blur-scope all)"
            APP_BLUR_SCOPE_EXPLICIT=1
        fi
    fi
}

# This run's answers back into the drawer, after everything has resolved.
save_glass_mode_memos() {
    mode_memo_write app-transparency "${APP_TRANSPARENCY:-0}"
    mode_memo_write app-tint-color   "${APP_TINT_COLOR:-#000000}"
    mode_memo_write shell-tint-color "${SHELL_TINT_COLOR:-#000000}"
    if [ "${GLASS_MODE:-}" = performance ]; then
        mode_memo_write app-blur-scope   "none"
        mode_memo_write popup-blur       "0"
    else
        mode_memo_write blur-strength    "${BLUR_STRENGTH:-100}"
        mode_memo_write blur-brightness  "${BLUR_BRIGHTNESS:-100}"
        mode_memo_write popup-opacity    "${POPUP_OPACITY:-main}"
        local entry surface var bvar
        for entry in $BLUR_SURFACES; do
            surface="${entry%%:*}"
            var="$(printf '%s' "$surface" | tr '[:lower:]' '[:upper:]')_BLUR_STRENGTH"
            bvar="$(printf '%s' "$surface" | tr '[:lower:]' '[:upper:]')_BRIGHTNESS"
            mode_memo_write "$surface-blur-strength"   "${!var:-main}"
            mode_memo_write "$surface-blur-brightness" "${!bvar:-main}"
        done
        mode_memo_write popup-blur       "${WANT_POPUP_BLUR:-1}"
        mode_memo_write app-blur-scope   "${APP_BLUR_SCOPE:-all}"
    fi
    return 0
}
