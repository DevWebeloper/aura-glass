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
GUI_ICON="$HOME/.local/share/icons/hicolor/scalable/apps/$GUI_APP_ID.svg"

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
    run install -Dm644 "$REPO_ROOT/gui/icons/$GUI_APP_ID.svg" "$GUI_ICON"
    if [ "${DRY_RUN:-0}" != 1 ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -qft "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

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
Icon=$GUI_APP_ID
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

# Arm the settings window to open itself once, on the login after this install.
#
# An install ends by asking for a logout, and that logout is where it stops
# being visible: the next session comes up with everything changed and nothing
# saying so, and the window that would show it is a name someone has to know to
# search for. Opening it once, unprompted, is the difference between a theme
# that landed and a theme that landed where you could see it.
#
# XDG autostart rather than a systemd user unit, unlike the three units this
# project already installs: those run headless programs that only talk to the
# bus, whereas this one has to put a window on a screen, and autostart is
# launched by the session with a session's environment already around it.
#
# There is nothing to switch off, because the entry deletes itself the first
# time it runs (see bin/aura-glass-open-once) — it is one window, once, and by
# the time anyone could want it gone it already is. Re-running the installer
# before that login rewrites the same path, so it still opens exactly once.
#
# Not called from the --settings-only path. That path changes settings from the
# window and needs no logout, so there is no next session to catch and nothing
# the window could show that is not already on screen.
install_first_open_autostart() {
    step "Opening the settings window next login"

    # The same two conditions install_gui installs under. Asked again rather
    # than inferred from $GUI_DESKTOP existing, so a --no-gui run over an older
    # install — which leaves the old entry on disk — does not arm a window the
    # user just asked not to have.
    if [ "${WANT_GUI:-1}" != 1 ]; then
        skip "no settings window to open (--no-gui)"
        return 0
    fi
    if ! gui_toolkit_present; then
        skip "the settings window was not installed, so there is nothing to open"
        return 0
    fi

    local autostart="$HOME/.config/autostart/aura-glass-open-once.desktop"

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-open-once" \
        "$HOME/.local/bin/aura-glass-open-once"

    # Absolute Exec for the reason install_gui's entry gives: ~/.local/bin is
    # not reliably on the PATH the session launches an autostart entry with.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: write $autostart"
    else
        mkdir -p "$(dirname "$autostart")"
        cat > "$autostart" <<EOF
[Desktop Entry]
Type=Application
Name=Aura Glass (first run)
Comment=Show the Aura Glass settings window once after installing
Exec=$HOME/.local/bin/aura-glass-open-once
Icon=$GUI_APP_ID
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        chmod 644 "$autostart"
    fi

    ok "Aura Glass will open once when you log back in"
}

# The daily "is there a newer release" check.
#
# On by default, and the only thing in this project that talks to a network
# without being asked to at that moment — so it is a plain systemd user timer
# that can be turned off from the settings window or with --no-update-check, and
# the script it runs is readable in bin/. It asks the git remote for its tags.
# It does not fetch, does not touch the working tree, and never installs
# anything: installing is a button someone presses.
install_update_check() {
    step "Update notifications"

    local unit_dir="$HOME/.config/systemd/user"
    local memo="$CONF_DIR/update-check"

    # Remembered like every other choice here, so a flagless re-run does not turn
    # it back on over a deliberate --no-update-check.
    local want="${WANT_UPDATE_CHECK:-1}"
    if [ -z "${UPDATE_CHECK_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    # The check reads $CONF_DIR/repo-path and asks git about the checkout there,
    # so it is meaningless without one. A tarball download rather than a clone is
    # the ordinary way to end up here.
    if [ ! -d "$REPO_ROOT/.git" ]; then
        skip "not a git checkout — nothing to compare a release tag against"
        return 0
    fi

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-update-check" \
        "$HOME/.local/bin/aura-glass-update-check"

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run systemctl --user disable --now aura-glass-update-check.timer 2>/dev/null || true
        skip "daily update check off — run aura-glass-update-check by hand, or turn it on in the settings window"
        return 0
    fi

    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-update-check.service" \
        "$unit_dir/aura-glass-update-check.service"
    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-update-check.timer" \
        "$unit_dir/aura-glass-update-check.timer"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: systemctl --user enable --now aura-glass-update-check.timer"
        return 0
    fi

    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable --now aura-glass-update-check.timer >/dev/null 2>&1; then
        ok "daily update check on — you will get one notification per release"
    else
        warn "could not enable the update timer (no systemd user session?)"
        info "aura-glass-update-check still works when run by hand"
    fi
}
