# shellcheck shell=bash
# aura-glass — the three glass modes.
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
# Frosted and transparent apply that by leaving an explicit sub-flag's answer
# alone; solid has no tuning left to concede once the theme has stood down, so
# it applies the same rule by refusing the run instead of silently overruling
# one.

# The mode the resolved state amounts to, which is what gets remembered. Solid
# is the styling being down rather than the blur being off: --no-blur on its own
# is an opaque theme, not a theme that has stood down, and remembering it as
# solid would stand the styling down on the next flagless run.
glass_mode_from_state() {
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        printf 'solid\n'
    elif [ "${WANT_BLUR:-1}" = 1 ] && [ "${WANT_WINDOW_BLUR:-1}" = 0 ] \
         && [ "${APP_TRANSPARENCY:-0}" != 0 ]; then
        printf 'transparent\n'
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

    # The marker is the honest answer for solid: it is the state the desktop is
    # actually in, and it outranks a memo that a hand-edited install could have
    # left disagreeing with it.
    if [ -f "$CONF_DIR/styling-off" ]; then GLASS_MODE="solid"; return 0; fi

    if [ -r "$CONF_DIR/glass-mode" ]; then
        GLASS_MODE="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
        case " $VALID_GLASS_MODES " in
            *" $GLASS_MODE "*) return 0 ;;
        esac
    fi
    GLASS_MODE=""      # nothing to go on; apply_glass_mode leaves the flags be
}

# The table in the design doc, in code. Only ever writes a value whose flag was
# not given: --glass-mode transparent --no-popup-blur is a mode with one of its
# answers overruled, not a contradiction.
apply_glass_mode() {
    case "${GLASS_MODE:-}" in
        frosted)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=1
            [ -n "${WINDOW_BLUR_EXPLICIT:-}" ] || WANT_WINDOW_BLUR=1
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=1
            WANT_STYLING=1
            ;;
        transparent)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=1
            if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ]; then
                WANT_WINDOW_BLUR=0
                APP_BLUR_SCOPE="none"
            fi
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=1
            WANT_STYLING=1
            ;;
        solid)
            # Solid leaves Blur My Shell out entirely and installs no
            # translucency, so there is nothing left for --blur, --popup-blur or
            # --app-transparency to reach — refused rather than silently
            # discarded, the same call install.sh's own conflict check already
            # makes for --window-blur. Checked before anything below moves a
            # flag, so the die fires against what the user actually typed.
            if [ -n "${BLUR_EXPLICIT:-}" ] && [ "$WANT_BLUR" = 1 ]; then
                die "--glass-mode solid and --blur contradict each other — solid mode leaves Blur My Shell out entirely, so there is no blur for --blur to turn on. Pick one."
            fi
            if [ -n "${POPUP_BLUR_EXPLICIT:-}" ] && [ "$WANT_POPUP_BLUR" = 1 ]; then
                die "--glass-mode solid and --popup-blur contradict each other — solid mode leaves Blur My Shell out entirely, so there is no blur for --popup-blur to turn on. Pick one."
            fi
            if [ -n "${APP_TRANSPARENCY_EXPLICIT:-}" ]; then
                # Not a plain != 0: this runs before install.sh's own
                # transparency normalisation, deliberately, because a mode has
                # to resolve before the level it implies gets normalised — so
                # an off-shaped answer can still arrive spelled any of the ways
                # that normalisation later folds to 0 rather than as the
                # literal digit. Matched against that same set of spellings,
                # so --app-transparency 0.0 / 0% / off / none / no is the same
                # request as solid, not a contradiction of it.
                case "$APP_TRANSPARENCY" in
                    0|0.0|0%|off|none|no) ;;
                    *) die "--glass-mode solid and --app-transparency contradict each other — solid mode installs no translucency, so there is nothing for --app-transparency to set. Pick one." ;;
                esac
            fi
            WANT_BLUR=0
            WANT_POPUP_BLUR=0
            POPUP_BLUR_EXPLICIT=1
            # Window blur is the one flag in this list left unguarded here: an
            # explicit --window-blur is refused a step later, by install.sh's
            # own conflict check, which already names the mode when it fires.
            # Refusing it here too would just be that same check running twice
            # — so it is left standing, for that check to see and act on.
            [ -n "${WINDOW_BLUR_EXPLICIT:-}" ] || { WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1; }
            WANT_ROUNDED_BLUR=0
            APP_TRANSPARENCY=0
            APP_OPACITY=255
            WANT_STYLING=0
            ;;
        *)  # No mode to apply: a run driven by bare flags, on a machine that
            # has never been told about modes. The flags stand as given.
            ;;
    esac
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
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        : > "$CONF_DIR/styling-off"
    else
        rm -f "$CONF_DIR/styling-off"
    fi
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
    [ "${GLASS_MODE:-}" = solid ] && return 0

    local disk_level disk_app disk_shell disk_strength disk_scope disk_popup
    disk_level="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    disk_app="$(cat "$CONF_DIR/app-tint-color" 2>/dev/null || true)"
    disk_shell="$(cat "$CONF_DIR/shell-tint-color" 2>/dev/null || true)"
    disk_strength="$(cat "$CONF_DIR/blur-strength" 2>/dev/null || true)"
    disk_scope="$(cat "$CONF_DIR/app-blur-scope" 2>/dev/null || true)"
    disk_popup="$(cat "$CONF_DIR/popup-blur" 2>/dev/null || true)"

    if [ "${GLASS_MODE:-}" = transparent ]; then
        # Unconditional, not a fallback for an empty disk_level: the shared
        # top-level memo is frosted's tab, tuned for a blurred window behind
        # it, and a value living there — 0.88, 0, anything — was never
        # transparent's to inherit. Transparent has no history before it has
        # a drawer of its own, so its first seed is always this darker level.
        # The tint below is inherited despite that, and the asymmetry is the
        # point: a tint is a colour preference that travels with the user
        # regardless of mode, while the level is coupled to whether there is
        # blur behind the window, which is exactly the thing that changes
        # between modes — so one carries over and the other is the mode's
        # own answer.
        mode_memo_write app-transparency "0.82"
        mode_memo_write app-tint-color   "${disk_app:-#0b0b0f}"
        mode_memo_write shell-tint-color "${disk_shell:-#0b0b0f}"
    else
        mode_memo_write app-transparency "${disk_level:-0}"
        mode_memo_write app-tint-color   "${disk_app:-#000000}"
        mode_memo_write shell-tint-color "${disk_shell:-#000000}"
        mode_memo_write app-blur-scope   "${disk_scope:-gtk}"
    fi
    mode_memo_write blur-strength "${disk_strength:-100}"
    mode_memo_write popup-blur    "${disk_popup:-1}"
}

# The drawer into this run's variables. Only where the flag was not given, on
# the same precedence rule apply_glass_mode follows.
load_glass_mode_memos() {
    [ -n "${GLASS_MODE:-}" ] || return 0
    [ "${GLASS_MODE}" = solid ] && return 0

    # A value install.sh would refuse is treated as an empty drawer rather than
    # passed along: the flag it would become dies in the parser, which is a
    # failure a long way from the file that caused it.
    local level; level="$(mode_memo_read app-transparency 0)"
    case "$level" in
        0|0.[0-9][0-9]|1.00) ;;
        *) warn "$(mode_memo_path app-transparency) holds '$level' — reseeding this mode"
           rm -rf "$CONF_DIR/modes/$GLASS_MODE"
           seed_glass_mode ;;
    esac

    [ -n "${APP_TRANSPARENCY_EXPLICIT:-}" ] || [ -n "${APP_TRANSPARENCY:-}" ] \
        || APP_TRANSPARENCY="$(mode_memo_read app-transparency 0)"
    [ -n "${APP_TINT_COLOR:-}" ]   || APP_TINT_COLOR="$(mode_memo_read app-tint-color '#000000')"
    [ -n "${SHELL_TINT_COLOR:-}" ] || SHELL_TINT_COLOR="$(mode_memo_read shell-tint-color '#000000')"
    [ -n "${BLUR_STRENGTH:-}" ]    || BLUR_STRENGTH="$(mode_memo_read blur-strength 100)"

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
        WANT_POPUP_BLUR="$(mode_memo_read popup-blur 1)"
        POPUP_BLUR_EXPLICIT=1
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
    mode_memo_write popup-blur       "${WANT_POPUP_BLUR:-1}"
    [ "${GLASS_MODE:-}" = frosted ] && mode_memo_write app-blur-scope "${APP_BLUR_SCOPE:-gtk}"
    return 0
}
