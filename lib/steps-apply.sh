# shellcheck shell=bash
# The settings window's Apply: `install.sh --settings-only --incremental` with
# only the flags that changed. install.sh parses and resolves them as on every
# run (CLAUDE.md rule 1), resolve_apply_plan (steps-apply-plan.sh) classifies
# them into actions, and this runs those actions and nothing else. A plan of
# `full` never reaches here: install.sh falls back to the complete retune.
#
# Steps that every action would repeat are collected and run once at the end,
# so an accent edit that moves the icons and the cursor syncs the login screen
# once rather than once per action.

run_incremental_apply() {
    local part action look_ran=0 gdm_look=0
    if [ "$WANT_CURSORS" = 1 ] && { [ -n "$CURSORS_EXPLICIT" ] || { [ "${CURSORS:-}" = moga ] && [ -n "${ACCENT_EXPLICIT:-}" ]; }; }; then
        install_cursors
    fi
    step "Applying changed settings only"
    # What changed underneath since the last run goes first, as it does
    # on the full path: the look reads every flag, so its stylesheet
    # rewrite is the only one this Apply needs.
    for part in "${APPLY_PARTS[@]}"; do
        [ "$part" != look ] || look_ran=1
        run_update_part "$part"
    done
    for action in "${APPLY_ACTIONS[@]}"; do
        case "$action" in
            accent) apply_accent ;;
            update-check) install_update_check ;;
            window-menu) install_aura_ext ;;
            font) install_fonts; apply_font; gdm_look=1 ;;
            icons)
                if [ "$WANT_ICONS" = 1 ] && [ -n "$ICONS_EXPLICIT" ]; then install_icons; fi
                apply_icon_theme
                install_icon_sync
                gdm_look=1
                ;;
            radius) apply_radius_dconf ;;
            popup-blur) apply_popup_blur ;;
            cursor-theme) apply_cursor_theme; gdm_look=1 ;;
            cursor-size) apply_cursor_size; gdm_look=1 ;;
            window-buttons) apply_window_buttons ;;
            blur-pipelines) apply_blur_pipelines ;;
            app-blur) apply_app_blur ;;
            css) if [ "$look_ran" = 0 ]; then install_css; fi ;;
            app-opacity) apply_app_opacity ;;
            fullscreen-blur) apply_fullscreen_blur ;;
            maximized-blur) apply_maximized_blur ;;
            osd-device-name) apply_osd_device_name; sync_osd_profile ;;
            osd-style) apply_osd_style; sync_osd_profile ;;
            osd-background) apply_osd_background; sync_osd_profile ;;
            system-icons)
                apply_icon_theme
                install_icon_sync
                gdm_look=1
                ;;
            smooth-animations) apply_smooth_animations ;;
            animation-speed) apply_animation_speed ;;
            top-bar-icon) apply_top_bar_icon ;;
            glass-style) apply_glass_style ;;
            adaptive-blur)
                apply_adaptive_blur "$ADAPTIVE_BLUR"
                ;;
        esac
    done
    # The login screen mirrors the cursor, icons and font. Only that half of
    # the GDM sync, and once: the wallpaper half is the full retune's.
    [ "$gdm_look" = 0 ] || sync_gdm_look_only
    # The mode drawer is what the next full run, the settings window
    # and an adaptive restore all read these values back from. The
    # narrow path updated the top-level memos; without this the drawer
    # kept the previous tint/level and the next full Apply put it back.
    # An adaptive transition is transient and must not touch it.
    [ -n "$ADAPTIVE_BLUR" ] || remember_glass_mode
    if [ -z "$ADAPTIVE_BLUR" ] && [ "${#APPLY_PENDING[@]}" -gt 0 ]; then
        warn "these changed and need an update to install: ${APPLY_PENDING[*]}"
    fi
    step "Done"
}
