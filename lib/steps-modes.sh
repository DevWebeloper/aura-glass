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
            WANT_BLUR=0
            # Guarded, unlike the rest of this branch: solid means there is no
            # blur left to put behind a window, so an explicit --window-blur is
            # not something to silently overrule — it is left standing so the
            # conflict check below sees it and refuses the combination instead.
            [ -n "${WINDOW_BLUR_EXPLICIT:-}" ] || { WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1; }
            WANT_POPUP_BLUR=0
            POPUP_BLUR_EXPLICIT=1
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
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        : > "$CONF_DIR/styling-off"
    else
        rm -f "$CONF_DIR/styling-off"
    fi
}
