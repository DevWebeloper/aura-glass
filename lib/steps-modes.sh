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
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        : > "$CONF_DIR/styling-off"
    else
        rm -f "$CONF_DIR/styling-off"
    fi
}
