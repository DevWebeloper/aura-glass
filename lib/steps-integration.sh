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
        [ "$stopped" = 1 ] && run systemctl --user daemon-reload
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
    [ "$icon_unit_changed" = 1 ] && run systemctl --user daemon-reload
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

install_panel_blur_unit() {
    step "Blur My Shell panel blur rebuild"

    # This unit exists to toggle Blur My Shell's panel blur off and on once the
    # session has settled, so the actor is rebuilt against correct geometry.
    # With no Blur My Shell there is no actor and nothing to rebuild, so in
    # solid mode it is a timer that waits twelve seconds after every login to
    # do nothing. Checked here rather than in the flag parsing so that the flag
    # order cannot defeat it: --no-blur --full would otherwise turn it back on.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        WANT_PANEL_BLUR_FIX=0
    fi

    # Remembered like every other setting, so a later flagless run — and the
    # settings window, which reads the memo to draw the switch — comes back to
    # this answer rather than to the default. Written before the branch so it
    # records the choice whichever way it went.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${WANT_PANEL_BLUR_FIX:-1}" > "$CONF_DIR/panel-blur-fix"
    fi

    if [ "${WANT_PANEL_BLUR_FIX:-1}" != 1 ]; then
        # Clean up any previously installed panel blur units
        local found=0 u
        for u in aura-glass-panel-blur.service tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
            [ -f "$HOME/.config/systemd/user/$u" ] || continue
            found=1
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
            ok "removed $u"
        done
        [ "$found" = 1 ] && run systemctl --user daemon-reload
        skip "not installed (--no-panel-blur-fix)"
        return 0
    fi

    for u in tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
        if [ -f "$HOME/.config/systemd/user/$u" ]; then
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
        fi
    done

    local panel_command_changed=0 panel_unit_changed=0
    install_if_changed "$REPO_ROOT/bin/aura-glass-panel-blur" \
        "$HOME/.local/bin/aura-glass-panel-blur" 755
    panel_command_changed="$INSTALL_CHANGED"
    install_if_changed "$REPO_ROOT/tools/aura_glass_panel_blur.py" \
        "$HOME/.local/share/aura-glass/aura_glass_panel_blur.py" 755
    [ "$INSTALL_CHANGED" = 1 ] && panel_command_changed=1
    if [ "$(readlink "$HOME/.local/bin/tahoe-glass-panel-blur" 2>/dev/null || true)" != "$HOME/.local/bin/aura-glass-panel-blur" ]; then
        run ln -sfn "$HOME/.local/bin/aura-glass-panel-blur" "$HOME/.local/bin/tahoe-glass-panel-blur"
    fi
    install_if_changed "$REPO_ROOT/systemd/aura-glass-panel-blur.service" \
        "$HOME/.config/systemd/user/aura-glass-panel-blur.service" 644
    panel_unit_changed="$INSTALL_CHANGED"
    [ "$panel_unit_changed" = 1 ] && run systemctl --user daemon-reload
    if ! systemctl --user is-enabled --quiet aura-glass-panel-blur.service 2>/dev/null; then
        run systemctl --user enable aura-glass-panel-blur.service >/dev/null 2>&1 || true
    fi

    # enable only arms it for the next login, and the strip is on screen now.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        if systemctl --user is-active --quiet aura-glass-panel-blur.service 2>/dev/null; then
            if [ "$panel_command_changed" = 1 ] || [ "$panel_unit_changed" = 1 ]; then
                run systemctl --user restart aura-glass-panel-blur.service 2>/dev/null || true
            fi
        else
            run systemctl --user start aura-glass-panel-blur.service 2>/dev/null || true
        fi
    fi
    ok "panel blur rebuilds on every monitor change, and once at login"
}
