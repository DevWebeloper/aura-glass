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
            --accent|--accent=*) _apply_add accent ;;
            --cursor-size|--cursor-size=*) _apply_add cursor-size ;;
            --window-buttons|--window-buttons=*) _apply_add window-buttons ;;
            --app-blur-allow|--app-blur-allow=*|--app-blur-block|--app-blur-block=*) _apply_add app-blur ;;
            --app-tint-color|--app-tint-color=*|--shell-tint-color|--shell-tint-color=*|--app-transparency|--app-transparency=*|--no-app-transparency|--notification-opacity|--notification-opacity=*|--titlebar-button-style|--titlebar-button-style=*) _apply_add css ;;
            *) APPLY_FALLBACK_REASON="unclassified flag: $flag"; APPLY_ACTIONS=(full); return ;;
        esac
    done
    if [ "${#APPLY_ACTIONS[@]}" = 0 ]; then
        APPLY_FALLBACK_REASON="no narrow setting was typed"
        APPLY_ACTIONS=(full)
    fi
}

apply_source_fingerprint() {
    (cd "$REPO_ROOT" && sha256sum install.sh lib/*.sh tokens/tokens.sh bin/aura-glass-apply tools/aura_glass_operation.py css/*.css dconf/*.ini | sha256sum | cut -d' ' -f1)
}
