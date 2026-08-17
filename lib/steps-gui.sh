# shellcheck shell=bash
# aura-glass — the settings window.
#
# gui/aura_glass_settings.py is a front end for install.sh --settings-only and
# nothing more: it reads the $CONF_DIR memos, shows them, and shells out with the
# flags that changed. So installing it is three copies and a desktop entry, with
# no schema to compile and no service to register.
#
# It is optional in the way --icons is optional. PyGObject and libadwaita are not
# dependencies of a GTK theme, and a machine without them still gets every
# setting the window exposes, as flags.
#
# Sourced by install.sh.

GUI_DIR="$HOME/.local/share/aura-glass/gui"
GUI_APP_ID="io.github.DevWebeloper.AuraGlassSettings"
GUI_DESKTOP="$HOME/.local/share/applications/$GUI_APP_ID.desktop"

install_gui() {
    step "Settings window"

    if [ "${WANT_GUI:-1}" != 1 ]; then
        skip "not installed (--no-gui) — every setting it shows is still a flag"
        return 0
    fi

    if ! gui_toolkit_present; then
        warn "PyGObject or libadwaita is missing, so the settings window is"
        warn "being skipped. Nothing else is affected — it is a front end for"
        warn "flags this script already has."
        info "to get it: $(gui_toolkit_hint)"
        info "then re-run ./install.sh --settings-only"
        return 0
    fi

    run install -Dm644 "$REPO_ROOT/gui/aura_glass_settings.py" \
        "$GUI_DIR/aura_glass_settings.py"
    run install -Dm755 "$REPO_ROOT/bin/aura-glass-settings" \
        "$HOME/.local/bin/aura-glass-settings"

    # The window runs install.sh, which needs css/, dconf/ and lib/ beside it, so
    # it has to know where this checkout is. Recorded rather than guessed: by the
    # time anyone opens the window the shell it was installed from is long gone,
    # and a wrong guess would mean Apply silently reconfiguring from some other
    # copy of the project.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$REPO_ROOT" > "$CONF_DIR/repo-path"
    fi

    # Generated rather than shipped in gui/, for the same reason the density CSS
    # is generated in steps-css.sh: it is written for whatever $HOME the
    # installer is actually run in. Exec is absolute because ~/.local/bin is not
    # reliably on the PATH a desktop entry is launched with — finish() says as
    # much about aura-glass-apply — and a launcher that only works from a shell
    # would defeat the point of having an entry at all.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: write $GUI_DESKTOP"
    else
        mkdir -p "$(dirname "$GUI_DESKTOP")"
        cat > "$GUI_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Aura Glass
GenericName=Theme Settings
Comment=Retune the Aura Glass desktop — corner rounding, blur and accent
Exec=$HOME/.local/bin/aura-glass-settings
Icon=preferences-desktop-appearance
Terminal=false
Categories=GNOME;GTK;Settings;DesktopSettings;
Keywords=aura;glass;theme;blur;radius;corner;rounding;accent;appearance;
StartupNotify=true
StartupWMClass=$GUI_APP_ID
EOF
        chmod 644 "$GUI_DESKTOP"
    fi

    ok "settings window -> aura-glass-settings (and the Activities overview)"
}
