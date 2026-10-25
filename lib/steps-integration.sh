# shellcheck shell=bash
# aura-glass — the pieces that wire the desktop up.
#
# None of these change how anything looks. They exist because GNOME will
# otherwise undo, sandbox away, or mis-clip something the rest of the install
# just set: the icon key has no notion of a light/dark pair, a Flatpak app is
# sandboxed away from the GTK config, and Blur My Shell clips its panel actor to
# a geometry that is not settled at login.
#
# Sourced by install.sh.

# Colloid ships a -Light and a -Dark build of every accent; GNOME's icon-theme
# key holds exactly one name and knows nothing about the pair. Without this,
# switching Settings > Appearance to Light restyles everything except the
# icons, which stay dark and look wrong against the new background.
install_icon_sync() {
    step "Following the light/dark preference with the icons"

    # Not installed *and* stopped, because leaving it running is the same
    # override it exists to perform: the agent rewrites icon-theme on every
    # light/dark switch from the pack memo, so an agent left over from an
    # earlier run puts this theme's icons back over whatever was set from
    # anywhere else. Kept icons means nothing of ours writes that key.
    if [ "${WANT_ICONS:-1}" != 1 ]; then
        local unit stopped=0
        for unit in aura-glass-icon-sync tahoe-glass-icon-sync; do
            [ -f "$HOME/.config/systemd/user/$unit.service" ] || continue
            run systemctl --user disable --now "$unit.service" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$unit.service"
            stopped=1
        done
        [ "$stopped" = 1 ] && run systemctl --user daemon-reload || true
        skip "icons left alone (--no-icons) — the light/dark agent stood down"
        return 0
    fi

    # The base name without the variant suffix, which is what the agent needs
    # in order to find the light and dark halves of the pair.
    local base; base="$(icon_base)"

    # Clean legacy units if present
    if [ -f "$HOME/.config/systemd/user/tahoe-glass-icon-sync.service" ]; then
        run systemctl --user disable --now tahoe-glass-icon-sync.service >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/tahoe-glass-icon-sync.service"
    fi

    local icon_command_changed=0 icon_unit_changed=0
    install_if_changed "$REPO_ROOT/bin/aura-glass-icon-sync" \
        "$HOME/.local/bin/aura-glass-icon-sync" 755
    icon_command_changed="$INSTALL_CHANGED"
    if [ "$(readlink "$HOME/.local/bin/tahoe-glass-icon-sync" 2>/dev/null || true)" != "$HOME/.local/bin/aura-glass-icon-sync" ]; then
        run ln -sfn "$HOME/.local/bin/aura-glass-icon-sync" "$HOME/.local/bin/tahoe-glass-icon-sync"
    fi

    # The two memos this used to write live in remember_icon_pack now, called
    # from install_icons — this step does not run in the --settings-only path,
    # so a pack chosen from the window was never getting recorded here.

    install_if_changed "$REPO_ROOT/systemd/aura-glass-icon-sync.service" \
        "$HOME/.config/systemd/user/aura-glass-icon-sync.service" 644
    icon_unit_changed="$INSTALL_CHANGED"
    [ "$icon_unit_changed" = 1 ] && run systemctl --user daemon-reload || true
    if ! systemctl --user is-enabled --quiet aura-glass-icon-sync.service 2>/dev/null; then
        run systemctl --user enable aura-glass-icon-sync.service >/dev/null 2>&1 || true
    fi

    # enable alone only arms it for the next login, and there is no reason to
    # make the user log out to see their icons follow the theme.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        if systemctl --user is-active --quiet aura-glass-icon-sync.service 2>/dev/null; then
            if [ "$icon_command_changed" = 1 ] || [ "$icon_unit_changed" = 1 ]; then
                run systemctl --user restart aura-glass-icon-sync.service 2>/dev/null || true
            fi
        else
            run systemctl --user start aura-glass-icon-sync.service 2>/dev/null || true
        fi
    fi
    ok "icons follow Settings > Appearance ($(icon_variant "$base" Dark || echo "$base") / $(icon_variant "$base" Light || echo "$base"))"
}

# ------------------------------------------------------------- integration --

flatpak_override() {
    have flatpak || { skip "flatpak not installed"; return 0; }
    step "Letting Flatpak apps read the GTK config"

    # Without this a Flatpak app is sandboxed away from ~/.config/gtk-4.0 and
    # silently keeps stock Adwaita — which looks exactly like the tweaks
    # failing to apply.
    run flatpak override --user \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-data/themes:ro \
        --filesystem=xdg-data/icons:ro
    ok "read-only access granted to themes, icons and GTK config"
}

# The panel blur rebuild service toggled Blur My Shell's panel/blur false then
# true after every monitor change and once at login, to rebuild a panel blur
# sized against a layout that had since changed. The toggle itself flashed the
# bare top bar. patches/blur-my-shell-panel-refit.patch now refits that blur
# in place inside Blur My Shell, in one frame, so the service only costs a
# flash. Every run takes out whatever an earlier one installed, under all three
# names it has had, with its command and the memo that drove it.
remove_panel_blur_unit() {
    local found=0 u
    for u in aura-glass-panel-blur.service tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
        [ -f "$HOME/.config/systemd/user/$u" ] || continue
        [ "$found" = 1 ] || step "Removing the panel blur rebuild service (no longer needed)"
        found=1
        run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/$u"
        ok "removed $u"
    done
    [ "$found" = 1 ] && { run systemctl --user daemon-reload || true; }
    local f
    for f in "$HOME/.local/bin/aura-glass-panel-blur" \
             "$HOME/.local/bin/tahoe-glass-panel-blur" \
             "$HOME/.local/share/aura-glass/aura_glass_panel_blur.py" \
             "$CONF_DIR/panel-blur-fix"; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            run rm -f "$f"
        fi
    done
}

# Adaptive performance is a session observer, not a second settings resolver:
# its worker only asks install.sh to apply or restore a transient blur strength.
# Keep its three artifacts together so --settings-only refreshes the installed
# command and unit without fetching or changing any selected theme asset.
install_adaptive_performance() {
    step "Adaptive performance"

    run rm -rf "$EXT_DIR/aura-glass-adaptive@aura-glass.local"
    # Settings-only Apply does not run install_extensions/enable_extensions,
    # but the Aura first-party helper must arrive with this local refresh too.
    if [ "${SETTINGS_ONLY:-0}" = 1 ]; then
        install_aura_ext
        if [ -d "$EXT_DIR/$AURA_EXT_UUID" ] || \
           [ -d "/usr/share/gnome-shell/extensions/$AURA_EXT_UUID" ]; then
            if ! run gnome-extensions enable "$AURA_EXT_UUID" 2>/dev/null; then
                if [ "${DRY_RUN:-0}" = 1 ]; then
                    info "dry-run: add $AURA_EXT_UUID to enabled-extensions for the next session"
                elif enqueue_extension "$AURA_EXT_UUID"; then
                    ok "$AURA_EXT_UUID queued — active after logout"
                else
                    warn "could not enable $AURA_EXT_UUID"
                fi
            fi
        fi
    fi

    local command_changed=0 unit_changed=0
    install_if_changed "$REPO_ROOT/bin/aura-glass-adaptive" \
        "$HOME/.local/bin/aura-glass-adaptive" 755
    command_changed="$INSTALL_CHANGED"
    install_if_changed "$REPO_ROOT/tools/aura_glass_adaptive.py" \
        "$HOME/.local/share/aura-glass/aura_glass_adaptive.py" 755
    [ "$INSTALL_CHANGED" = 1 ] && command_changed=1
    install_if_changed "$REPO_ROOT/systemd/aura-glass-adaptive.service" \
        "$HOME/.config/systemd/user/aura-glass-adaptive.service" 644
    unit_changed="$INSTALL_CHANGED"

    # The profile is a user choice, so installation supplies Auto only once;
    # runtime state deliberately lives below adaptive-performance/ instead.
    if [ ! -r "$CONF_DIR/adaptive-profile" ] && [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' auto > "$CONF_DIR/adaptive-profile"
    fi
    # The worker applies through this checkout rather than through the optional
    # settings window's repo-path memo.  --no-gui is a supported install, and
    # the adaptive command must retain the same installer-owned writer there.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$REPO_ROOT/install.sh" > "$CONF_DIR/adaptive-install"
    fi

    if [ -z "${ADAPTIVE_BLUR:-}" ] && [ "${DRY_RUN:-0}" != 1 ]; then
        # A normal Apply has just reloaded the user's baseline.  Any prior
        # transient marker describes dconf that no longer exists, so clear it
        # before the worker samples again.
        mkdir -p "$CONF_DIR/adaptive-performance"
        printf '0\n' > "$CONF_DIR/adaptive-performance/active"
        printf 'normal\n' > "$CONF_DIR/adaptive-performance/reason"
    fi

    [ "$unit_changed" = 1 ] && run systemctl --user daemon-reload || true
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        # Performance has no blur to downshift. Stop the worker so it cannot
        # write Blur My Shell keys under it.
        run systemctl --user disable --now aura-glass-adaptive.service >/dev/null 2>&1 || true
        if [ "${DRY_RUN:-0}" != 1 ]; then
            # Any prior transient downshift is gone with the blur. Clear the
            # runtime marker so returning to glass can apply a fresh
            # battery/fullscreen/GPU decision instead of mistaking the old
            # state for the live dconf state.
            mkdir -p "$CONF_DIR/adaptive-performance"
            printf '0\n' > "$CONF_DIR/adaptive-performance/active"
            printf 'no-blur\n' > "$CONF_DIR/adaptive-performance/reason"
        fi
        skip "no blur — adaptive blur worker stood down"
        return 0
    fi
    if ! systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        # A service without the Shell session cannot ask the D-Bus fullscreen
        # method, so do not leave an old unit active when Apply runs from a
        # text-only user manager.
        run systemctl --user disable --now aura-glass-adaptive.service >/dev/null 2>&1 || true
        skip "not enabled outside a graphical session"
        return 0
    fi

    if ! systemctl --user is-enabled --quiet aura-glass-adaptive.service 2>/dev/null; then
        run systemctl --user enable aura-glass-adaptive.service >/dev/null 2>&1 || true
    fi
    if systemctl --user is-active --quiet aura-glass-adaptive.service 2>/dev/null; then
        if [ "$command_changed" = 1 ] || [ "$unit_changed" = 1 ]; then
            run systemctl --user restart aura-glass-adaptive.service >/dev/null 2>&1 || true
        fi
    else
        run systemctl --user start aura-glass-adaptive.service >/dev/null 2>&1 || true
    fi
    ok "Auto watches fullscreen, battery and supported GPU load"

    if [ -z "${ADAPTIVE_BLUR:-}" ] && [ "${DRY_RUN:-0}" != 1 ]; then
        if [ -x "$HOME/.local/bin/aura-glass-adaptive" ]; then
            "$HOME/.local/bin/aura-glass-adaptive" refresh >/dev/null 2>&1 || true
        fi
    fi
}
