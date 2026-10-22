# shellcheck shell=bash
# Conservative selector for settings-only incremental Apply. Resolution stays in
# install.sh; this file only classifies the flags a caller actually typed.

APPLY_ACTIONS=()
APPLY_FALLBACK_REASON=""

_apply_add() { local value; for value in "${APPLY_ACTIONS[@]}"; do [ "$value" = "$1" ] && return; done; APPLY_ACTIONS+=("$1"); }

select_apply_actions() {
    APPLY_ACTIONS=()
    APPLY_FALLBACK_REASON=""
    local flag
    for flag in "${TYPED_FLAGS[@]}"; do
        case "$flag" in
            --settings-only|--incremental|--plan-json|--yes|-y|--dry-run|-n) ;;
            --adaptive-blur|--adaptive-blur=*) _apply_add adaptive-blur ;;
            --accent|--accent=*) _apply_add accent ;;
            --cursor-size|--cursor-size=*) _apply_add cursor-size ;;
            --cursors|--cursors=*|--no-cursors) _apply_add cursor-theme ;;
            --window-buttons|--window-buttons=*) _apply_add window-buttons ;;
            --window-brightness|--window-brightness=*|--app-brightness|--app-brightness=*) _apply_add window-brightness ;;
            --fullscreen-blur|--no-fullscreen-blur) _apply_add fullscreen-blur ;;
            --blur-refresh|--blur-refresh=*) _apply_add blur-refresh ;;
            --app-blur-allow|--app-blur-allow=*|--app-blur-block|--app-blur-block=*) _apply_add app-blur ;;
            # The level is written twice: the GTK stylesheet's alpha (css) and
            # Blur My Shell's window actor opacity, which is all a browser or
            # Electron window has. Classed as css alone, a slider move rewrote
            # the sheet and left the actor at its old value, so Chrome stopped
            # showing the blur while GTK apps still did.
            --app-transparency|--app-transparency=*|--no-app-transparency) _apply_add css; _apply_add app-opacity ;;
            --app-tint-color|--app-tint-color=*|--shell-tint-color|--shell-tint-color=*|--notification-opacity|--notification-opacity=*|--titlebar-button-style|--titlebar-button-style=*) _apply_add css ;;
            *) APPLY_FALLBACK_REASON="unclassified flag: $flag"; APPLY_ACTIONS=(full); return ;;
        esac
    done
    if [ "${#APPLY_ACTIONS[@]}" = 0 ]; then
        APPLY_FALLBACK_REASON="no narrow setting was typed"
        APPLY_ACTIONS=(full)
        return
    fi
    # The settings window sends only --accent for an accent edit. Moga is the
    # one pointer pack whose selected theme name depends on that value, so the
    # incremental path must update the cursor key beside the accent key.
    if [ "${CURSORS:-}" = moga ] && [ -n "${ACCENT_EXPLICIT:-}" ]; then
        _apply_add cursor-theme
    fi
    # The tinted glass style is coloured with the accent (accent_hex in
    # steps-dconf.sh), so an accent edit has to re-tint the shell too.
    if [ -n "${ACCENT_EXPLICIT:-}" ] && [ "$(cat "$CONF_DIR/glass-style" 2>/dev/null || true)" = tinted ]; then
        _apply_add glass-style
    fi
}

apply_source_fingerprint() {
    (cd "$REPO_ROOT" && sha256sum install.sh lib/*.sh tokens/tokens.sh bin/aura-glass-apply tools/aura_glass_operation.py css/*.css dconf/*.ini | sha256sum | cut -d' ' -f1)
}
