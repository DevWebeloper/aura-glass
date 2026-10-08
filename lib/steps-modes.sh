# shellcheck shell=bash
# aura-glass — the glass modes (frosted and performance).
#
# A mode is not a fourth kind of setting — it is a name for a combination of the
# blur, transparency and styling flags install.sh already has, plus a drawer to
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
            WANT_STYLING=1
            ;;
        performance)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=0
            if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ]; then
                WANT_WINDOW_BLUR=0
                APP_BLUR_SCOPE="none"
            fi
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=0
            [ -n "${NOTIFICATION_BLUR_EXPLICIT:-}" ] || WANT_NOTIFICATION_BLUR=0
            if [ -z "${APP_TRANSPARENCY_EXPLICIT:-}" ]; then
                APP_TRANSPARENCY=0.99
                APP_OPACITY=252
            fi
            WANT_STYLING=1
            ;;
        *)  # No mode to apply: a run driven by bare flags, on a machine that
            # has never been told about modes. The flags stand as given.
            ;;
    esac
}

# Writes or removes $CONF_DIR/styling-off to match WANT_STYLING — the marker
# bin/aura-glass-apply reads to decide whether to splice the block in or stand
# it down. Called from two places, for two different reasons: install_css calls
# it before aura-glass-apply runs, because the marker has to already be on disk
# for that mid-run read to see it; remember_glass_mode calls it again once the
# run has fully resolved, because that is what leaves it in the right state
# once install.sh is done. Each caller keeps its own DRY_RUN guard around the
# call, so this does not need one of its own.
sync_styling_marker() {
    mkdir -p "$CONF_DIR"
    if [ "${WANT_STYLING:-1}" = 0 ]; then : > "$CONF_DIR/styling-off"
    else rm -f "$CONF_DIR/styling-off"; fi
}

# Written after the run has resolved, so the memo holds what was applied rather
# than what was asked for. The marker is the styling half of the same answer and
# is written here too, so the two can never disagree.
remember_glass_mode() {
    GLASS_MODE="$(glass_mode_from_state)"
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$GLASS_MODE" > "$CONF_DIR/glass-mode"
    save_glass_mode_memos
    sync_styling_marker
}

# ---- the per-mode drawer ------------------------------------------------

# Every mode keeps the settings that belong to it. The top-level memos stay the
# live state — install_transparency_css, apply_app_tint_color and the settings
# window all read those, and none of them learn about modes — so these are an
# archive that the mode switch restores from, not a second source of truth.
mode_memo_path() { printf '%s/modes/%s/%s\n' "$CONF_DIR" "${GLASS_MODE:-frosted}" "$1"; }

mode_memo_read() {   # KEY DEFAULT
    local f; f="$(mode_memo_path "$1")"
    if [ -r "$f" ]; then cat "$f" 2>/dev/null || printf '%s\n' "$2"
    else printf '%s\n' "$2"; fi
}

mode_memo_write() {  # KEY VALUE
    mkdir -p "$CONF_DIR/modes/${GLASS_MODE:-frosted}"
    printf '%s\n' "$2" > "$(mode_memo_path "$1")"
}

# What a mode starts life with. Read from the top-level memos where they exist,
# so an install that predates modes keeps the tuning it is wearing and finds it
# in the tab it belongs to; from the constants only where there is nothing to
# read. Transparent is the exception that proves it: with no blur behind the
# window the wallpaper is what the text sits on, so it starts darker, and a
# level of 0 is not a state this mode has.
seed_glass_mode() {
    local dir="$CONF_DIR/modes/${GLASS_MODE:-frosted}"
    [ -d "$dir" ] && return 0
    mkdir -p "$dir"

    local disk_level disk_app disk_shell disk_strength disk_scope disk_popup disk_notification
    local disk_brightness disk_ground
    disk_level="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    disk_app="$(cat "$CONF_DIR/app-tint-color" 2>/dev/null || true)"
    disk_shell="$(cat "$CONF_DIR/shell-tint-color" 2>/dev/null || true)"
    disk_strength="$(cat "$CONF_DIR/blur-strength" 2>/dev/null || true)"
    disk_scope="$(cat "$CONF_DIR/app-blur-scope" 2>/dev/null || true)"
    disk_popup="$(cat "$CONF_DIR/popup-blur" 2>/dev/null || true)"
    disk_notification="$(cat "$CONF_DIR/notification-blur" 2>/dev/null || true)"
    disk_brightness="$(cat "$CONF_DIR/popup-brightness" 2>/dev/null || true)"
    disk_ground="$(cat "$CONF_DIR/notification-opacity" 2>/dev/null || true)"

    if [ "${GLASS_MODE:-}" = performance ]; then
        mode_memo_write app-transparency "0.99"
        mode_memo_write app-tint-color   "${disk_app:-#000000}"
        mode_memo_write shell-tint-color "${disk_shell:-#000000}"
        mode_memo_write app-blur-scope   "none"
        mode_memo_write popup-blur       "0"
        mode_memo_write notification-blur "0"
    else
        mode_memo_write app-transparency "${disk_level:-0}"
        mode_memo_write app-tint-color   "${disk_app:-#000000}"
        mode_memo_write shell-tint-color "${disk_shell:-#000000}"
        mode_memo_write app-blur-scope   "${disk_scope:-gtk}"
    fi
    mode_memo_write blur-strength    "${disk_strength:-100}"
    # Both seed to the preset rather than to a neutral 100 and 50: what ships
    # in dconf/core.ini and css/shell-notification-blur.css is the tuned look,
    # and a drawer that seeded elsewhere would move the desktop the first time
    # a mode was opened.
    mode_memo_write popup-brightness "${disk_brightness:-115}"
    mode_memo_write notification-opacity "${disk_ground:-40}"
    if [ "${GLASS_MODE:-}" != performance ]; then
        mode_memo_write popup-blur       "${disk_popup:-1}"
        mode_memo_write notification-blur "${disk_notification:-1}"
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
    [ "${GLASS_MODE}" = performance ] && def_t=0.99
    local level; level="$(mode_memo_read app-transparency "$def_t")"
    case "$level" in
        0|0.[0-9][0-9]|1.00) ;;
        *) warn "$(mode_memo_path app-transparency) holds '$level' — reseeding this mode"
           rm -rf "$CONF_DIR/modes/$GLASS_MODE"
           seed_glass_mode ;;
    esac

    [ -n "${APP_TRANSPARENCY_EXPLICIT:-}" ] || [ -n "${APP_TRANSPARENCY:-}" ] \
        || APP_TRANSPARENCY="$(mode_memo_read app-transparency "$def_t")"
    [ -n "${APP_TINT_COLOR:-}" ]   || APP_TINT_COLOR="$(mode_memo_read app-tint-color '#000000')"
    [ -n "${SHELL_TINT_COLOR:-}" ] || SHELL_TINT_COLOR="$(mode_memo_read shell-tint-color '#000000')"
    [ -n "${BLUR_STRENGTH:-}" ]    || BLUR_STRENGTH="$(mode_memo_read blur-strength 100)"
    [ -n "${POPUP_BRIGHTNESS:-}" ] || POPUP_BRIGHTNESS="$(mode_memo_read popup-brightness 115)"
    [ -n "${NOTIFICATION_OPACITY:-}" ] || NOTIFICATION_OPACITY="$(mode_memo_read notification-opacity 40)"

    # *_EXPLICIT has meant "the user typed the flag" up to here; from the
    # point one of these is set below it means "settled for this run,
    # whether by a flag or by the mode's drawer, so leave it alone" — because
    # each of these two markers has a reader further down that goes back to
    # the shared top-level memo whenever it finds the marker unset:
    # apply_popup_blur for POPUP_BLUR_EXPLICIT, and both install.sh's own
    # resolution block a few lines below and apply_app_blur for
    # APP_BLUR_SCOPE_EXPLICIT — both in lib/steps-dconf.sh. Without setting it
    # here, a value the drawer just loaded would survive exactly until the
    # next line that tests the marker, then lose to whatever the top-level
    # memo (tuned for a different mode) happens to hold.
    if [ -z "${POPUP_BLUR_EXPLICIT:-}" ]; then
        local def_pb=1
        [ "${GLASS_MODE}" = performance ] && def_pb=0
        WANT_POPUP_BLUR="$(mode_memo_read popup-blur "$def_pb")"
        POPUP_BLUR_EXPLICIT=1
    fi
    if [ -z "${NOTIFICATION_BLUR_EXPLICIT:-}" ]; then
        local def_nb=1
        [ "${GLASS_MODE}" = performance ] && def_nb=0
        WANT_NOTIFICATION_BLUR="$(mode_memo_read notification-blur "$def_nb")"
        NOTIFICATION_BLUR_EXPLICIT=1
    fi
    # Transparent has no scope to remember: not blurring behind windows is what
    # the mode is, and apply_glass_mode has already pinned it to none.
    if [ "${GLASS_MODE}" = frosted ] && [ -z "${APP_BLUR_SCOPE_EXPLICIT:-}" ]; then
        APP_BLUR_SCOPE="$(mode_memo_read app-blur-scope gtk)"
        APP_BLUR_SCOPE_EXPLICIT=1
    fi
}

# This run's answers back into the drawer, after everything has resolved.
save_glass_mode_memos() {
    [ "${WANT_STYLING:-1}" = 0 ] && return 0
    mode_memo_write app-transparency "${APP_TRANSPARENCY:-0}"
    mode_memo_write app-tint-color   "${APP_TINT_COLOR:-#000000}"
    mode_memo_write shell-tint-color "${SHELL_TINT_COLOR:-#000000}"
    mode_memo_write blur-strength    "${BLUR_STRENGTH:-100}"
    mode_memo_write popup-brightness "${POPUP_BRIGHTNESS:-115}"
    mode_memo_write notification-opacity "${NOTIFICATION_OPACITY:-40}"
    mode_memo_write popup-blur       "${WANT_POPUP_BLUR:-1}"
    mode_memo_write notification-blur "${WANT_NOTIFICATION_BLUR:-1}"
    [ "${GLASS_MODE:-}" = frosted ] && mode_memo_write app-blur-scope "${APP_BLUR_SCOPE:-gtk}"
    return 0
}
